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
    @Published var cardOpacity: Double { didSet { store.set(cardOpacity, forKey: Key.cardOpacity.rawValue) } }
    @Published var cardIntensity: Double { didSet { store.set(cardIntensity, forKey: Key.cardIntensity.rawValue) } }
    @Published var cardFontScale: Double { didSet { store.set(cardFontScale, forKey: Key.cardFontScale.rawValue) } }
    @Published var appearanceMode: AppearanceMode { didSet { store.set(appearanceMode.rawValue, forKey: Key.appearanceMode.rawValue) } }

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
        case cardOpacity = "omlx.cardOpacity"
        case cardIntensity = "omlx.cardIntensity"
        case cardFontScale = "omlx.cardFontScale"
        case appearanceMode = "omlx.appearanceMode"
        case floatingFrame = "omlx.floatingFrame"
    }

    static let defaultServer = ServerConfig(name: "家里的 Mac Studio", urlString: "http://127.0.0.1:7979")
    static let defaultSSHTarget = "windnchen@172.47.68.21"

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
        let storedOpacity = UserDefaults.standard.double(forKey: Key.cardOpacity.rawValue)
        self.cardOpacity = min(1.0, max(0.3, storedOpacity > 0 ? storedOpacity : 1.0))
        let storedIntensity = UserDefaults.standard.object(forKey: Key.cardIntensity.rawValue) as? Double
        self.cardIntensity = min(1.0, max(0.0, storedIntensity ?? 0.5))
        let storedScale = UserDefaults.standard.object(forKey: Key.cardFontScale.rawValue) as? Double
        self.cardFontScale = min(1.4, max(0.8, storedScale ?? 1.0))
        self.appearanceMode = storedAppearance ?? .system
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
}
