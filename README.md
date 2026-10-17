# oMLX 桌面小工具

原生 macOS 菜单栏 + 桌面浮窗，用来看家里那台跑 oMLX 的机器：实时生成速度、token 用量、
统一内存压力、模型加载状态。零第三方依赖，只需要 Xcode Command Line Tools。

## 能看什么

- **实时生成速度**（tokens/s）：推理瞬间取服务端逐请求统计值，空闲时按 token 增量估算并快速衰减，配一条迷你速度曲线
- **请求中 / 排队数**
- **多任务多色曲线**：同时有两个以上请求在吐字时，速度曲线区自动换成**每个任务一条自己的曲线**，
  8 色循环配色跟着请求走（老任务滑出窗口不会让后面任务变色），每条只画该任务真正在生成那一段，右端点小圆点收尾。
  曲线下方换上一行同色图例（取前 3 条，其余折成 `+N`），面板里的逐请求行也用同一个颜色，方便对号；
  只剩一个任务时回到原来那条绿色总速度曲线、内存进度条归位。
  浮窗里这一行的优先级是「预填充文案 > 多任务图例 > 内存进度条」
- **预填充**：蓝色显示预填充速度与进度，含"已处理 / 总 token"、百分比与耗时；桌面浮窗在预填充期间
  直接把**整张卡片当进度条**——半透明蓝从左往右漫过卡面、描边变蓝、右边沿给一条亮蓝进度头，
  卡片上另有一行蓝色"预填充 88% · 1316 t/s"。蓝色压在文字下方，低透明度时字依旧清楚；
  进度未知时改成整卡呼吸式微蓝，不会出现空白的进度条
- **统一内存占用**：进度条上标出 oMLX 的软/硬阈值，右侧给"内存充裕 / 接近上限 / 内存吃紧"
- **GPU 与温度**：GPU 占用（Device / Renderer / Tiler）、GPU 显存、CPU 占用与负载、CPU / GPU 摄氏度、
  整机功耗与风扇转速，右上角给"正常 / 偏热 / 很热 / 过热"热度标签
- **今日用量**：请求数、tokens、缓存命中率、平均耗时、生成/预填充均速，外加今日 24 小时用量柱状图和最近 7 天总量
- **模型清单**：是否已加载、体积、上下文长度、常驻标记、引擎类型，可一键加载 / 卸载
- **测速按钮**：往默认模型发一条小请求，返回端到端 tokens/s（含首字延迟），适合刚换配置时对比
- **菜单栏标题**实时显示速度，可切"状态 + 速度 / 仅速度 / 仅状态点"
- **桌面浮窗**按住卡片任意位置都能拖走并记住位置（拖动时不会掉出屏幕可视区，右上角 ✕ 只在"没拖动"时生效），
  可选置顶或普通层级；设置里三个滑块分别调**不透明度**（30%～100%，
  只作用在背景，文字与图表始终满强度绘制）、**字色亮度**（0～100%）、**字号**（80%～140%，整卡等比放大）。
  亮度档位逐级叠加：小字对比度提到纯白、文字与图形叠同色辉光、卡面垫一层 `.textBackgroundColor`
  对比衬底（深浅色自适应）、进度条与速度曲线同步提亮并在高档位加粗。实测不透明度 35% 时文字峰值亮度
  仍有 0.95（按旧的"内容一起变透明"写法只有 0.80）；全不透明时小字与卡面亮度差 0.43，约为最初版本的 3.6 倍
- **白天 / 夜晚外观**：设置里"外观"可切**跟随系统 / 白天 / 夜晚**，面板底部也有个日夜按钮点着轮转。
  浮窗、详情面板、设置窗口一起换肤；字色亮度的方向跟着翻——深色底往纯白提亮，浅色底往纯黑压深，
  两种外观都是拉开与卡面的对比。**状态栏图标不跟着染**，始终按系统本身的深浅色上色，避免"深字压深底"看不见

## 用法

```bash
./build.sh --run      # 编译并启动
./build.sh --release  # 优化编译
./build.sh --install  # 复制到 /Applications
./build.sh --dmg      # 打成 dmg 安装包放到桌面（隐含 --release）
```

菜单栏出现小圆点即成功：

- 左键：弹出 / 收起详情面板（面板里也能测速、开关浮窗、进设置）
- 右键：菜单（立即刷新 / 发送测速请求 / 桌面浮窗 / 浮窗置顶 / 打开控制台 / 设置 / 退出）
- 再次启动 App（或从访达双击）等同于弹出面板
- 设置里可打开"登录后自动启动"

## 打成安装包

`./build.sh --dmg` 产出 `~/Desktop/oMLX 小工具 <版本>.dmg`：打开是 App 加一个 `Applications` 快捷方式，
拖过去就装好，另带一份 `安装说明.txt`。要点：

- 版本号取自 `build.sh` 里的 `VERSION`，改了名字跟着变
- 本机 ad-hoc 签名、没做公证：自己用没问题，发给别人首次打开要右键 → 打开确认一次
- 打包用 `ditto --noextattr` 且暂存在桌面之外，否则桌面开了 iCloud 同步会给 `.app` 补
  `com.apple.FinderInfo`，`codesign --strict` 判定"detritus not allowed"，别人打开会报"已损坏"
- 图标是 `Tools/make-icon.swift` 用 CoreGraphics 画的（照浮窗画的：卡面 + 蓝色预填充漫过 + 三条任务曲线），
  改完重画一次 icns：
  `xcrun swiftc -O Tools/make-icon.swift -o /tmp/make-icon && /tmp/make-icon /tmp/AppIcon-1024.png`，
  再用 `sips` 缩放成 `AppIcon.iconset` 各尺寸、`iconutil -c icns` 合成 `Resources/AppIcon.icns`

## 连接哪台 oMLX

默认地址 `http://127.0.0.1:7979`，也就是已经在跑的 SSH 隧道 LaunchAgent
`ai.hermes.omlx-tunnel`（本地 7979 → 远端 127.0.0.1:7979）。

- 局域网直连：设置里填 `http://192.168.31.191:7979`（`/admin/api/server-info` 会列出该机的别名和端口）
- 本机 oMLX：`http://127.0.0.1:8000`
- 多台机器：设置里"添加服务器"，点左侧圆圈切换当前服务器；切换后曲线与统计会重置重算
- 只想临时试一个地址：`OMLX_WIDGET_URL=http://127.0.0.1:8000 ".build/oMLX 小工具.app/Contents/MacOS/omlx-widget" &`

如果 oMLX 开了鉴权，在设置里填 API Key（以 `Authorization: Bearer <key>` 发送）。

## GPU 与温度（走 SSH）

oMLX 的 HTTP 接口不吐 GPU 占用和温度（它自己的控制台也只有 `ProcessInfo.thermalState` 这个热度档位），
所以这部分由小工具通过 `ssh` 在远端跑几条**零权限**命令采集，默认目标 `windnchen@172.47.68.21`，
在设置 → "GPU 与温度" 里可改地址或整个关掉。

- GPU 占用 / 显存：`ioreg -rd1 -c IOAccelerator` 的 `PerformanceStatistics`
- CPU 占用与负载：`iostat` + `sysctl vm.loadavg`
- 降频状态：`pmset -g therm`
- 摄氏度与风扇：`macmon pipe -s 1`（免 sudo），找不到时卡片会提示装一下：

```bash
# 在 Studio 上执行一次即可，小工具有装就用，没装也能看占用
brew install macmon
```

采集走 `ControlMaster` 复用连接，一次约 2 秒（缺 macmon 时约 4 秒），与 HTTP 轮询各跑各的循环，
互不阻塞；SSH 不通时卡片显示失败原因，不影响速度 / 用量等其余功能。

菜单栏还能切成"GPU + 温度"档，直接显示 `GPU 97% · 62°`。

## 用到的接口

只读：

- `GET /api/status` — 版本、运行时长、请求数、累计 token、平均速度、模型内存
- `GET /admin/api/activity` — 逐请求实时 `tokens_per_second`、预填充/排队队列、内存压力软硬阈值
- `GET /admin/api/usage?range=today|7d` — 今日/七日汇总与 24 小时 token 分布
- `GET /v1/models/status` — 模型清单、体积、上下文长度、加载状态

动作：

- `POST /v1/models/{id}/load`、`POST /v1/models/{id}/unload`
- `POST /v1/chat/completions`（测速请求，约 160 tokens）

轮询：状态与活动按设置间隔拉取（默认 3 秒），用量与模型清单约 45 秒一次，打开面板时立即全量刷新。

注意：GPU 占用、温度、功耗、风扇**不来自 HTTP 接口**，见上一节的 SSH 采集说明。

## 排障

- **显示"离线 / 连不上服务器"**：隧道或 oMLX 没起。先 `curl http://127.0.0.1:7979/api/status` 自检；
  需要时 `launchctl kickstart -k gui/$(id -u)/ai.hermes.omlx-tunnel` 重连隧道
- **速度数字跳动或归零**：`tokens/s` 只反映采样窗口内的真实吐字，空闲时几秒内归零属正常；
  要看长期表现用今日面板里的"生成均速"
- **编译报 `@State` 宏找不到**：本项目刻意不使用 SwiftUI 宏（CLT 单独安装时缺 `SwiftUIMacros` 插件），
  若改代码请避免 `@State` / `@Binding` / `@Observable`
- **GPU 与温度卡片空白 / 报 SSH 连接失败**：小工具靠 `ssh` 免密登录远端，先手动确认
  `ssh windnchen@172.47.68.21 'ioreg -rd1 -c IOAccelerator | head'` 能出东西；换了机器就改设置里的地址
- **温度显示"—"但 GPU 占用正常**：远端没装 macmon，或不在 `/opt/homebrew/bin` / `/usr/local/bin`，
  `brew install macmon` 后下一个轮询周期就有了
- **预填充行一闪而过**：预填充通常只有 1～3 秒，面板按设置间隔采样；prompt 越长停留越久。
  反复发同一段文本会命中前缀缓存、几乎不产生预填充，想盯着进度看就换一段全新长文本
- **多任务曲线挤在右边**：所有曲线与服务端轮询同一时间轴对齐，任务从它开始吐字的那一刻画起，
  之前是留白，所以空闲很久之后一起来的任务都靠在右侧；曲线窗口固定 90 个采样点
- **面板高度不够**：中间区域可滚动，模型多时向下滚
- **切了日夜但菜单栏图标没变**：有意如此。菜单栏由系统着色，小工具只把浮窗 / 面板 / 设置窗口切过去，
  状态栏图标固定按系统深浅色绘制，否则会出现系统浅色、图标也变浅导致的"隐形"

## 代码结构

- `Sources/main.swift` — 入口
- `Sources/AppController.swift` — 状态栏项、桌面浮窗、设置窗口。浮窗的拖动和关闭点击由
  `FloatingPanel.sendEvent` 自己接管：SwiftUI 的 hosting view 会吃掉 `mouseDown`，
  `isMovableByWindowBackground` 在这种窗口上不生效，命中区见 `FloatingCardLayout.closeRect`
- `Sources/Model/WidgetState.swift` — 轮询、实时速度推算、加载/卸载与测速动作
- `Sources/Model/SystemCollector.swift` — 通过 SSH 采集 GPU 占用、温度、功耗、风扇并解析
- `Sources/Model/OmlxClient.swift` / `OmlxAPI.swift` — HTTP 客户端与接口模型
- `Sources/Model/Preferences.swift` — 服务器列表与偏好持久化
- `Sources/UI/` — 面板、浮窗卡片、设置页与图表组件；`Parts.swift` 里的 `Appearance` 负责日夜外观判定与调色方向
- `Tools/make-icon.swift` / `Resources/AppIcon.icns` — App 图标的生成脚本与产物

## 可以继续加

- 历史 t/s 与温度曲线：直接读远端 `~/.omlx/usage.sqlite3` 的 `model_usage_hourly`
- KV / SSD 缓存命中、集群节点（`/admin/api/*` 已有对应接口）
- 加载确认弹窗、全局快捷键、断线自动重连提示
