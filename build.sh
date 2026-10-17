#!/bin/bash
# 构建 oMLX 桌面小工具（原生 AppKit/SwiftUI，零第三方依赖）
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="oMLX 小工具"
BUILD_DIR=".build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
BIN_NAME="omlx-widget"
BUNDLE_ID="local.windinchen.omlx-widget"
VERSION="1.8"

MODE="debug"
RUN_AFTER=0
INSTALL_AFTER=0
DMG_AFTER=0

for arg in "$@"; do
  case "$arg" in
    --release) MODE="release" ;;
    --run) RUN_AFTER=1 ;;
    --install) INSTALL_AFTER=1 ;;
    --dmg) DMG_AFTER=1; MODE="release" ;;
    -h|--help)
      cat <<USAGE
用法: ./build.sh [--release] [--run] [--install] [--dmg]
  --release  优化编译（稍慢）
  --run      构建后立刻启动
  --install  复制到 /Applications 并覆盖同名版本
  --dmg      打成 dmg 安装包放到桌面（隐含 --release）
USAGE
      exit 0 ;;
    *) echo "未知参数: $arg" >&2; exit 1 ;;
  esac
done

echo "==> 清理旧构建"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$BIN_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key><false/>
    <key>NSHumanReadableCopyright</key><string>本地 oMLX 状态小工具</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

# 图标：Tools/make-icon.swift 生成 PNG，iconutil 合成 icns
if [ -f Resources/AppIcon.icns ]; then
  echo "==> 放入图标"
  cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
else
  echo "==> 未找到 Resources/AppIcon.icns，用默认图标"
fi

SOURCES=()
while IFS= read -r source_file; do
  SOURCES+=("$source_file")
done < <(find Sources -name '*.swift' | sort)
FLAGS=(-swift-version 5 -target arm64-apple-macosx14.0 -framework AppKit -framework SwiftUI)
if [ "$MODE" = "release" ]; then
  FLAGS+=(-O)
fi

echo "==> 编译 ($MODE)"
xcrun swiftc "${FLAGS[@]}" -o "$APP_DIR/Contents/MacOS/$BIN_NAME" "${SOURCES[@]}" 2>&1 | sed 's/^/    /'
test -x "$APP_DIR/Contents/MacOS/$BIN_NAME"

echo "==> 本地签名"
# 桌面开了 iCloud 同步时 fileproviderd 会往 .app 上贴 FinderInfo / fpfs 扩展属性，
# codesign --strict 判定 "detritus not allowed"，而且清完可能立刻被重新贴上。
# 因此先把包挪到桌面之外签名，签好再拷回 .build，dmg 也直接用签好的那份
SCRATCH_DIR="$(mktemp -d "${TMPDIR:-/tmp}/omlx-widget-sign.XXXXXX")"
SIGN_APP="$SCRATCH_DIR/$APP_NAME.app"

sign_bundle() {
  local target="$1"
  find "$target" -name '._*' -delete 2>/dev/null || true
  xattr -cr "$target" 2>/dev/null || true
  codesign --force --sign - --timestamp=none "$target" >/dev/null 2>&1 \
    || codesign --force --sign - "$target"
}

ditto --noextattr --norsrc "$APP_DIR" "$SIGN_APP"
SIGN_OK=0
for _ in 1 2 3; do
  if sign_bundle "$SIGN_APP" && codesign --verify --deep --strict "$SIGN_APP" >/dev/null 2>&1; then
    SIGN_OK=1
    break
  fi
  sleep 1
done
test "$SIGN_OK" = "1" || { echo "签名失败：$SIGN_APP" >&2; exit 1; }
rm -rf "$APP_DIR"
ditto --noextattr --norsrc "$SIGN_APP" "$APP_DIR"

echo "==> 产出: $APP_DIR"

if [ "$INSTALL_AFTER" = "1" ]; then
  echo "==> 安装到 /Applications"
  rm -rf "/Applications/$APP_NAME.app"
  ditto --noextattr --norsrc "$SIGN_APP" "/Applications/$APP_NAME.app"
  echo "    /Applications/$APP_NAME.app"
fi

if [ "$DMG_AFTER" = "1" ]; then
  DMG_PATH="$HOME/Desktop/$APP_NAME $VERSION.dmg"
  echo "==> 打包 dmg 安装包"
  # 暂存放桌面之外：桌面开了 iCloud 同步时会给 .app 重新贴 FinderInfo，签名严格校验判定"detritus not allowed"
  STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/omlx-widget-dmg.XXXXXX")"
  ditto --noextattr --norsrc "$SIGN_APP" "$STAGE_DIR/$APP_NAME.app"
  ln -s /Applications "$STAGE_DIR/Applications"
  cat > "$STAGE_DIR/安装说明.txt" <<NOTES
$APP_NAME $VERSION 安装说明

1. 把 "oMLX 小工具.app" 拖到旁边的 "Applications" 文件夹（拖一次就够）
2. 从"应用程序"里启动，菜单栏出现小圆点即成功；左键点它弹出详情面板，
   再次启动 App 也等同于弹出面板
3. macOS 若提示"无法验证开发者"，右键 App 图标 → 打开，确认一次即可
   （本机 ad-hoc 签名，没做公证）

想开机自启：面板右下角齿轮进设置，打开"登录后自动启动"
GPU 占用 / 温度 / 功耗 / 风扇走 SSH 采集（默认 windnchen@172.47.68.21），
换机器就改设置里的地址，并确认本机能免密 ssh 到那台
NOTES
  # 桌面上还挂着旧镜像时先弹掉，弹不掉就换个带时间的文件名，别让打包在最后一步失败
  hdiutil detach "$DMG_PATH" -force >/dev/null 2>&1 || true
  rm -f "$DMG_PATH" || DMG_PATH="$HOME/Desktop/$APP_NAME $VERSION-$(date +%H%M%S).dmg"
  hdiutil create -quiet -nospotlight -volname "$APP_NAME $VERSION" \
    -srcfolder "$STAGE_DIR" -format UDZO -o "$DMG_PATH"
  rm -rf "$STAGE_DIR"
  echo "    $DMG_PATH"
fi

if [ "$RUN_AFTER" = "1" ]; then
  echo "==> 启动"
  open "$APP_DIR"
fi

rm -rf "$SCRATCH_DIR"
