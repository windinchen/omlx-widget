import SwiftUI
import ServiceManagement

final class SettingsModel: ObservableObject {
    @Published var message: String?
    @Published var launchAtLogin = false
}

struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var state: WidgetState
    @ObservedObject var model: SettingsModel
    @ObservedObject var updater: UpdateChecker

    init(
        prefs: Preferences = Preferences.shared,
        state: WidgetState = WidgetState.shared,
        model: SettingsModel = SettingsModel()
    ) {
        self.prefs = prefs
        self.state = state
        self.model = model
        self.updater = UpdateChecker.shared
    }

    var body: some View {
        Form {
            Section("服务器") {
                ForEach(prefs.servers) { server in
                    HStack(spacing: 8) {
                        Image(systemName: server.id == prefs.activeServerID ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(server.id == prefs.activeServerID ? Color.accentColor : Color.secondary)
                            .onTapGesture { prefs.activeServerID = server.id }
                        TextField("名称", text: nameBinding(server.id))
                            .frame(maxWidth: 130)
                        TextField("http://127.0.0.1:8000", text: urlBinding(server.id))
                            .font(.system(size: 11).monospacedDigit())
                        Button(role: .destructive) {
                            remove(server)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(prefs.servers.count <= 1)
                    }
                    .padding(.vertical, 2)
                }
                HStack {
                    Button {
                        add()
                    } label: {
                        Label("添加服务器", systemImage: "plus")
                    }
                    Spacer()
                    SecureField("API Key（可选）", text: $prefs.apiKey)
                        .frame(maxWidth: 180)
                }
                Text("家外的机器可以先起一条 SSH 隧道，再把地址填成 http://127.0.0.1:<本地端口>。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Section("刷新与显示") {
                Picker("外观", selection: $prefs.appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Picker("浮窗样式", selection: $prefs.cardStyle) {
                    ForEach(CardStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                Picker("菜单栏内容", selection: $prefs.menuBarMode) {
                    ForEach(MenuBarMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Stepper(value: $prefs.pollSeconds, in: 1...60, step: 1) {
                    HStack {
                        Text("刷新间隔")
                        Spacer()
                        Text("\(Int(prefs.pollSeconds)) 秒")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle("显示今日 24 小时用量柱状图", isOn: $prefs.showHeatmap)
                Toggle("显示桌面浮窗", isOn: $prefs.showFloatingCard)
                Toggle("浮窗保持置顶", isOn: $prefs.floatingTopmost)
                    .disabled(!prefs.showFloatingCard)
                HStack(spacing: 8) {
                    Text("浮窗不透明度")
                    Slider(value: $prefs.cardOpacity, in: 0.3...1.0)
                        .frame(maxWidth: 170)
                    Text("\(Int((prefs.cardOpacity * 100).rounded()))%")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
                HStack(spacing: 8) {
                    Text("浮窗字色亮度")
                    Slider(value: $prefs.cardIntensity, in: 0...1)
                        .frame(maxWidth: 170)
                    Text("\(Int((prefs.cardIntensity * 100).rounded()))%")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
                HStack(spacing: 8) {
                    Text("浮窗字号")
                    Slider(value: $prefs.cardFontScale, in: 0.8...1.4)
                        .frame(maxWidth: 170)
                    Text("\(Int((prefs.cardFontScale * 100).rounded()))%")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
                Text("亮度档位同时提高文字对比度、进度条与速度曲线的亮度和饱和度，白天模式改成往深色压；字号改动会等比放大整张卡片。浮窗多任务样式只影响桌面小卡片：速度曲线是多条同色曲线加图例，横向柱状是每个任务一行按快慢排序的柱子；详情面板始终画曲线。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Section("GPU 与温度") {
                Toggle("采集 GPU 利用率与温度", isOn: $prefs.systemMetricsEnabled)
                Picker("采集来源", selection: $prefs.systemSourceMode) {
                    ForEach(SystemSourceChoice.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!prefs.systemMetricsEnabled)
                TextField("SSH 目标（user@host）", text: $prefs.sshTarget)
                    .font(.system(size: 11).monospacedDigit())
                    .disabled(!prefs.systemMetricsEnabled || prefs.systemSourceMode == .local)
                Toggle("菜单栏改成显示 GPU 与温度", isOn: menuBarGPUBinding)
                    .disabled(!prefs.systemMetricsEnabled)
                Text(prefs.systemSourceMode.hint)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("两种来源跑的是同一套命令：ioreg / iostat / pmset，远程那一路走 ssh（需要先配好免密登录）。温度和风扇读数来自 macmon：brew install macmon，没装也能看 GPU 占用与降频状态。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                if let snapshot = state.system {
                    HStack {
                        Text("最近一次采集")
                        Spacer()
                        Text(snapshot.source.isLocal ? "本机" : "SSH")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(snapshot.hasAnyValue
                             ? "\(Fmt.clock(snapshot.date)) · \(snapshot.macmonReady ? "含温度" : "无温度源")"
                             : (snapshot.error ?? "无数据"))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(snapshot.hasAnyValue ? Palette.kind(.busy) : Color.secondary)
                    }
                }
            }
            Section("系统") {
                Toggle("登录后自动启动", isOn: $model.launchAtLogin)
                    .onChange(of: model.launchAtLogin) {
                        applyLogin(model.launchAtLogin)
                    }
                HStack {
                    Text("当前状态")
                    Spacer()
                    Text(state.isOnline ? "\(state.serverName) · \(state.loadedCount) 个模型已加载" : (state.lastError ?? "离线"))
                        .font(.system(size: 11))
                        .foregroundStyle(state.isOnline ? Palette.kind(.busy) : Color.secondary)
                        .lineLimit(1)
                }
            }
            updateSection

            if let message = model.message {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 660)
        .onAppear { model.launchAtLogin = (SMAppService.mainApp.status == .enabled) }
    }

    /// 版本与更新：本机版本号、GitHub 上的最新发布版、手动检查与开关
    /// 单独抽出来是因为 Form 里的东西堆到一起，编译器就算不出类型了
    @ViewBuilder
    private var updateSection: some View {
        HStack {
            Text("本机版本")
            Spacer()
            Text("v\(AppVersion.current.description)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        HStack {
            Text("GitHub 上")
            Spacer()
            Text(updateStatus.label)
                .font(.system(size: 11))
                .foregroundStyle(updateStatus.tint)
                .lineLimit(1)
            Text(updater.lastChecked == nil ? "从未检查" : "查于 \(Fmt.clock(updater.lastChecked))")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        HStack(spacing: 8) {
            GhostButton(title: updater.checkingLabel, systemImage: "arrow.triangle.2.circlepath") {
                Task {
                    await updater.check()
                    AppController.shared?.showUpdateWindow()
                }
            }
            GhostButton(title: "更新内容", systemImage: "text.page") {
                AppController.shared?.showUpdateWindow()
            }
            GhostButton(title: "发布页", systemImage: "safari") {
                if let url = updater.releasesURL ?? updater.homeURL {
                    NSWorkspace.shared.open(url)
                }
            }
            if !prefs.dismissedUpdateVersion.isEmpty {
                GhostButton(title: "别再忽略 \(prefs.dismissedUpdateVersion)", systemImage: "eye") {
                    updater.resetDismiss()
                }
            }
        }
        Toggle("启动后自动检查（之后每 6 小时一次）", isOn: $prefs.autoCheckUpdates)
        TextField("GitHub 仓库（owner/repo 或完整链接）", text: $prefs.githubRepository)
            .font(.system(size: 11).monospacedDigit())
        Text("版本号每次发布进 0.01（1.9 之后是 1.10），比对按点分段逐段比数值，不会把 1.10 当成比 1.9 旧。发现新版本时状态栏圆点会长出橙点，面板顶部出现横幅；更新完的第一次启动会弹一次更新内容，说明读自安装包里的 ReleaseNotes.md 与 GitHub 上那条 Release 的正文。")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
    }

    private var menuBarGPUBinding: Binding<Bool> {
        Binding(
            get: { prefs.menuBarMode == .gpu },
            set: { enabled in prefs.menuBarMode = enabled ? .gpu : .full }
        )
    }

    /// 设置里"GitHub 上"那一行的文案与颜色
    private var updateStatus: (label: String, tint: Color) {
        switch updater.status {
        case .idle: return ("还没查过", Color.secondary)
        case .checking: return ("正在检查…", Color.accentColor)
        case .upToDate: return ("已是最新版", Palette.kind(.busy))
        case .ahead(let release): return ("本机比 \(release.tagName) 更新", Palette.kind(.loading))
        case .available(let release): return ("有新版本 \(release.tagName)", Palette.kind(.loading))
        case .failed(let message): return (message, Palette.kind(.offline))
        }
    }

    private func nameBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { prefs.servers.first(where: { $0.id == id })?.name ?? "" },
            set: { value in update(id) { $0.name = value } }
        )
    }

    private func urlBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { prefs.servers.first(where: { $0.id == id })?.urlString ?? "" },
            set: { value in update(id) { $0.urlString = value } }
        )
    }

    private func update(_ id: UUID, transform: (inout ServerConfig) -> Void) {
        guard let index = prefs.servers.firstIndex(where: { $0.id == id }) else { return }
        transform(&prefs.servers[index])
    }

    private func add() {
        prefs.servers.append(ServerConfig(name: "新服务器", urlString: "http://127.0.0.1:8000"))
    }

    private func remove(_ server: ServerConfig) {
        prefs.servers.removeAll { $0.id == server.id }
        if prefs.activeServerID == server.id {
            prefs.activeServerID = prefs.servers.first?.id ?? Preferences.defaultServer.id
        }
    }

    private func applyLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                model.message = "已加入登录项。"
            } else {
                try SMAppService.mainApp.unregister()
                model.message = "已取消登录项。"
            }
        } catch {
            model.message = "登录项设置失败：\(error.localizedDescription)"
        }
    }
}
