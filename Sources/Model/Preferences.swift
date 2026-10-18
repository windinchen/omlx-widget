import Foundation
import Combine

struct ServerConfig: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    var urlString: String

    var url: URL? {
        var raw = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return nil }
        if !raw.contains("://") { raw = "http://" + raw }
        return URL(string: raw)
    }

    var displayHost: String {
        guard let url, let host = url.host else { return urlString }
        return url.port.map { "\(host):\($0)" } ?? host
    }
}

enum MenuBarMode: String, CaseIterable, Identifiable, Codable {
    case full
    case speed
    case gpu
    case iconOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .full: return "状态 + 速度"
        case .speed: return "仅速度"
        case .gpu: return "GPU + 温度"
        case .iconOnly: return "仅状态点"
        }
    }
}

/// 白天 / 夜晚外观；跟随系统时不去覆盖 AppKit 的外观
enum AppearanceMode: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "白天"
        case .dark: return "夜晚"
        }
    }

    /// 面板上的日夜按钮按这个顺序轮转
    var next: AppearanceMode {
        switch self {
        case .system: return .light
        case .light: return .dark
        case .dark: return .system
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon.fill"
        }
    }
}

/// GPU / CPU / 温度从哪儿采：远程走 SSH，本机直接在本地跑同一套命令，
/// 自动则按采集目标是不是这台机器自己来定
enum SystemSourceChoice: String, CaseIterable, Identifiable, Codable {
    case auto
    case remote
    case local

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "自动"
        case .remote: return "远程 SSH"
        case .local: return "本机"
        }
    }

    var hint: String {
        switch self {
        case .auto: return "采集目标是本机（localhost、机器名或本机任一 IP）就走本机采集，否则走 SSH"
        case .remote: return "始终通过 SSH 在远端采集，需要免密登录"
        case .local: return "始终在这台机器上采集，不用开远程登录"
        }
    }
}

/// 浮窗怎么排：多任务速度区画叠在一起的曲线还是每任务一行横向柱状，以及整张卡片的版式
enum CardStyle: String, CaseIterable, Identifiable, Codable {
    case curves
    case bars
    case gauge

    var id: String { rawValue }

    var label: String {
        switch self {
        case .curves: return "速度曲线"
        case .bars: return "横向柱状"
        case .gauge: return "竖向仪表"
        }
    }

    var symbol: String {
        switch self {
        case .curves: return "waveform.path.ecg"
        case .bars: return "chart.bar.horizontal"
        case .gauge: return "gauge.with.dots.needle.bottom.50percent"
        }
    }
}

final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let store = UserDefaults.standard

    @Published var servers: [ServerConfig] { didSet { persist(servers) } }
    @Published var activeServerID: UUID { didSet { store.set(activeServerID.uuidString, forKey: Key.activeServerID.rawValue) } }
    @Published var apiKey: String { didSet { store.set(apiKey, forKey: Key.apiKey.rawValue) } }
    @Published var pollSeconds: Double { didSet { store.set(pollSeconds, forKey: Key.pollSeconds.rawValue) } }
    @Published var menuBarMode: MenuBarMode { didSet { store.set(menuBarMode.rawValue, forKey: Key.menuBarMode.rawValue) } }
    @Published var showFloatingCard: Bool { didSet { store.set(showFloatingCard, forKey: Key.floatingCard.rawValue) } }
    @Published var floatingTopmost: Bool { didSet { store.set(floatingTopmost, forKey: Key.floatingTopmost.rawValue) } }
    @Published var showHeatmap: Bool { didSet { store.set(showHeatmap, forKey: Key.showHeatmap.rawValue) } }
    @Published var systemMetricsEnabled: Bool { didSet { store.set(systemMetricsEnabled, forKey: Key.systemMetrics.rawValue) } }
    @Published var sshTarget: String { didSet { store.set(sshTarget, forKey: Key.sshTarget.rawValue) } }
    @Published var systemSourceMode: SystemSourceChoice { didSet { store.set(systemSourceMode.rawValue, forKey: Key.systemSource.rawValue) } }
    @Published var cardOpacity: Double { didSet { store.set(cardOpacity, forKey: Key.cardOpacity.rawValue) } }
    @Published var cardIntensity: Double { didSet { store.set(cardIntensity, forKey: Key.cardIntensity.rawValue) } }
    @Published var cardFontScale: Double { didSet { store.set(cardFontScale, forKey: Key.cardFontScale.rawValue) } }
    @Published var appearanceMode: AppearanceMode { didSet { store.set(appearanceMode.rawValue, forKey: Key.appearanceMode.rawValue) } }
    @Published var cardStyle: CardStyle { didSet { store.set(cardStyle.rawValue, forKey: Key.cardStyle.rawValue) } }
    @Published var autoCheckUpdates: Bool { didSet { store.set(autoCheckUpdates, forKey: Key.autoCheckUpdates.rawValue) } }
    @Published var githubRepository: String { didSet { store.set(githubRepository, forKey: Key.githubRepository.rawValue) } }
    /// 用户点过"忽略这个版本"的小版本号：只在版本号和 GitHub 上那个完全相同时才屏蔽
    @Published var dismissedUpdateVersion: String { didSet { store.set(dismissedUpdateVersion, forKey: Key.dismissedUpdateVersion.rawValue) } }

    private enum Key: String {
        case servers = "omlx.servers"
        case activeServerID = "omlx.activeServerID"
        case apiKey = "omlx.apiKey"
        case pollSeconds = "omlx.pollSeconds"
        case menuBarMode = "omlx.menuBarMode"
        case floatingCard = "omlx.floatingCard"
        case floatingTopmost = "omlx.floatingTopmost"
        case showHeatmap = "omlx.showHeatmap"
        case systemMetrics = "omlx.systemMetrics"
        case sshTarget = "omlx.sshTarget"
        case systemSource = "omlx.systemSource"
        case cardOpacity = "omlx.cardOpacity"
        case cardIntensity = "omlx.cardIntensity"
        case cardFontScale = "omlx.cardFontScale"
        case appearanceMode = "omlx.appearanceMode"
        case cardStyle = "omlx.cardStyle"
        case floatingFrame = "omlx.floatingFrame"
        case autoCheckUpdates = "omlx.autoCheckUpdates"
        case githubRepository = "omlx.githubRepo"
        case dismissedUpdateVersion = "omlx.dismissedUpdateVersion"
        case lastUpdateCheck = "omlx.lastUpdateCheck"
        case lastReleaseData = "omlx.lastReleaseData"
        case lastLaunchedVersion = "omlx.lastLaunchedVersion"
    }

    static let defaultServer = ServerConfig(name: "家里的 Mac Studio", urlString: "http://127.0.0.1:7979")
    static let defaultSSHTarget = "windnchen@172.47.68.21"
    static let defaultRepository = "windinchen/omlx-widget"

    private init() {
        var loaded: [ServerConfig]?
        if let data = UserDefaults.standard.data(forKey: Key.servers.rawValue) {
            loaded = try? JSONDecoder().decode([ServerConfig].self, from: data)
        }
        let resolvedServers = (loaded?.isEmpty == false) ? loaded! : [Preferences.defaultServer]

        var resolvedID = UserDefaults.standard.string(forKey: Key.activeServerID.rawValue).flatMap(UUID.init(uuidString:))
        if resolvedID == nil || !resolvedServers.contains(where: { $0.id == resolvedID }) {
            resolvedID = resolvedServers.first?.id
        }

        let storedMode = UserDefaults.standard.string(forKey: Key.menuBarMode.rawValue).flatMap(MenuBarMode.init(rawValue:))
        let storedAppearance = UserDefaults.standard.string(forKey: Key.appearanceMode.rawValue).flatMap(AppearanceMode.init(rawValue:))
        let storedCardStyle = UserDefaults.standard.string(forKey: Key.cardStyle.rawValue).flatMap(CardStyle.init(rawValue:))
        let storedSystemSource = UserDefaults.standard.string(forKey: Key.systemSource.rawValue).flatMap(SystemSourceChoice.init(rawValue:))
        let storedPoll = UserDefaults.standard.double(forKey: Key.pollSeconds.rawValue)

        self.servers = resolvedServers
        self.activeServerID = resolvedID ?? resolvedServers[0].id
        self.apiKey = UserDefaults.standard.string(forKey: Key.apiKey.rawValue) ?? ""
        self.pollSeconds = storedPoll >= 1 ? storedPoll : 3
        self.menuBarMode = storedMode ?? .full
        self.showFloatingCard = UserDefaults.standard.object(forKey: Key.floatingCard.rawValue) as? Bool ?? true
        self.floatingTopmost = UserDefaults.standard.object(forKey: Key.floatingTopmost.rawValue) as? Bool ?? true
        self.showHeatmap = UserDefaults.standard.object(forKey: Key.showHeatmap.rawValue) as? Bool ?? true
        self.systemMetricsEnabled = UserDefaults.standard.object(forKey: Key.systemMetrics.rawValue) as? Bool ?? true
        self.sshTarget = UserDefaults.standard.string(forKey: Key.sshTarget.rawValue) ?? Preferences.defaultSSHTarget
        self.systemSourceMode = storedSystemSource ?? .auto
        let storedOpacity = UserDefaults.standard.double(forKey: Key.cardOpacity.rawValue)
        self.cardOpacity = min(1.0, max(0.3, storedOpacity > 0 ? storedOpacity : 1.0))
        let storedIntensity = UserDefaults.standard.object(forKey: Key.cardIntensity.rawValue) as? Double
        self.cardIntensity = min(1.0, max(0.0, storedIntensity ?? 0.5))
        let storedScale = UserDefaults.standard.object(forKey: Key.cardFontScale.rawValue) as? Double
        self.cardFontScale = min(1.4, max(0.8, storedScale ?? 1.0))
        self.appearanceMode = storedAppearance ?? .system
        self.cardStyle = storedCardStyle ?? .curves
        self.autoCheckUpdates = UserDefaults.standard.object(forKey: Key.autoCheckUpdates.rawValue) as? Bool ?? true
        self.githubRepository = UserDefaults.standard.string(forKey: Key.githubRepository.rawValue) ?? Preferences.defaultRepository
        self.dismissedUpdateVersion = UserDefaults.standard.string(forKey: Key.dismissedUpdateVersion.rawValue) ?? ""
    }

    private func persist(_ value: [ServerConfig]) {
        if let data = try? JSONEncoder().encode(value) {
            store.set(data, forKey: Key.servers.rawValue)
        }
    }

    var activeServer: ServerConfig {
        if let override = ProcessInfo.processInfo.environment["OMLX_WIDGET_URL"],
           override.hasPrefix("http"),
           URL(string: override) != nil {
            return ServerConfig(name: "临时地址", urlString: override)
        }
        return servers.first(where: { $0.id == activeServerID }) ?? servers.first ?? Preferences.defaultServer
    }

    var floatingFrame: String? {
        get { store.string(forKey: Key.floatingFrame.rawValue) }
        set { store.set(newValue, forKey: Key.floatingFrame.rawValue) }
    }

    /// 上一次真的去 GitHub 问的时间，0 表示从没问过
    var lastUpdateCheck: TimeInterval {
        get { store.double(forKey: Key.lastUpdateCheck.rawValue) }
        set { store.set(newValue, forKey: Key.lastUpdateCheck.rawValue) }
    }

    /// 上一次查到的 Release，重启后面板立刻有得显示，不用等网络
    var lastReleaseData: Data {
        get { store.data(forKey: Key.lastReleaseData.rawValue) ?? Data() }
        set { store.set(newValue, forKey: Key.lastReleaseData.rawValue) }
    }

    /// 上一次启动时的版本号；和这次的不一样的话就是刚更新过，要弹一次更新内容
    var lastLaunchedVersion: String {
        get { store.string(forKey: Key.lastLaunchedVersion.rawValue) ?? "" }
        set { store.set(newValue, forKey: Key.lastLaunchedVersion.rawValue) }
    }
}
