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

    init(
        prefs: Preferences = Preferences.shared,
        state: WidgetState = WidgetState.shared,
        model: SettingsModel = SettingsModel()
    ) {
        self.prefs = prefs
        self.state = state
        self.model = model
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
                TextField("SSH 目标（user@host）", text: $prefs.sshTarget)
                    .font(.system(size: 11).monospacedDigit())
                    .disabled(!prefs.systemMetricsEnabled)
                Toggle("菜单栏改成显示 GPU 与温度", isOn: menuBarGPUBinding)
                    .disabled(!prefs.systemMetricsEnabled)
                Text("小工具通过 ssh 在 Studio 上跑 ioreg / iostat / pmset（需要先配好免密登录）。温度和风扇读数来自 macmon：brew install macmon，没装也能看 GPU 占用与降频状态。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                if let snapshot = state.system {
                    HStack {
                        Text("最近一次采集")
                        Spacer()
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

            if let message = model.message {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 620)
        .onAppear { model.launchAtLogin = (SMAppService.mainApp.status == .enabled) }
    }

    private var menuBarGPUBinding: Binding<Bool> {
        Binding(
            get: { prefs.menuBarMode == .gpu },
            set: { enabled in prefs.menuBarMode = enabled ? .gpu : .full }
        )
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
