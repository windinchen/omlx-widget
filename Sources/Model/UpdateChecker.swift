import Foundation
import Combine
import SwiftUI

/// 版本号：按点分段逐段比数值。字典序会说谎——"1.9" > "1.10"，本项目的版本号偏偏就是这么进的
struct AppVersion: Comparable, CustomStringConvertible {
    var parts: [Int]

    init(parts: [Int]) { self.parts = parts }

    init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        let pieces = text.split(separator: ".").map(String.init)
        guard !pieces.isEmpty else { return nil }
        var numbers: [Int] = []
        for piece in pieces {
            let digits = piece.prefix(while: \.isNumber)
            guard !digits.isEmpty, let value = Int(digits) else { return nil }
            numbers.append(value)
        }
        parts = numbers
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    var description: String { parts.map(String.init).joined(separator: ".") }

    /// 安装包里的版本号；OMLX_WIDGET_VERSION 可以假装自己是旧版本，方便本地试更新提示
    static var current: AppVersion {
        let raw = ProcessInfo.processInfo.environment["OMLX_WIDGET_VERSION"]
            ?? (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            ?? "0"
        return AppVersion(raw) ?? AppVersion(parts: [0])
    }
}

struct GitHubAsset: Codable, Equatable {
    var name: String?
    var size: Int?
    var browserDownloadURL: String?

    enum CodingKeys: String, CodingKey {
        case name, size
        case browserDownloadURL = "browser_download_url"
    }
}

struct GitHubRelease: Codable, Equatable {
    var tagName: String
    var name: String?
    var body: String?
    var htmlURL: String?
    var publishedAt: String?
    var draft: Bool?
    var prerelease: Bool?
    var assets: [GitHubAsset]?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name, body, draft, prerelease, assets
        case htmlURL = "html_url"
        case publishedAt = "published_at"
    }

    var version: AppVersion? { AppVersion(tagName) }
    var pageURL: URL? { htmlURL.flatMap(URL.init(string:)) }

    /// 优先给 dmg，没有 dmg 就退回第一个资产
    var downloadURL: URL? {
        let urls = (assets ?? []).compactMap { $0.browserDownloadURL }.compactMap(URL.init(string:))
        return urls.first { $0.pathExtension.lowercased() == "dmg" } ?? urls.first
    }

    var publishedText: String? {
        guard let publishedAt else { return nil }
        let reader = ISO8601DateFormatter()
        reader.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = reader.date(from: publishedAt) ?? { () -> Date? in
            let plain = ISO8601DateFormatter()
            return plain.date(from: publishedAt)
        }()
        guard let date else { return nil }
        let writer = DateFormatter()
        writer.locale = Locale(identifier: "zh_CN")
        writer.dateFormat = "M 月 d日 HH:mm"
        return writer.string(from: date)
    }
}

enum UpdateStatus: Equatable {
    case idle
    case checking
    case upToDate
    /// 本机版本比 GitHub 上最新的发布版还新（自己打的开发包，或者 CI 还没跑完）
    case ahead(GitHubRelease)
    case available(GitHubRelease)
    case failed(String)

    var release: GitHubRelease? {
        switch self {
        case .available(let release), .ahead(let release): return release
        default: return nil
        }
    }

    var isUpdateAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

enum UpdateError: LocalizedError {
    case noRepository
    case noRelease
    case transport(String)
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .noRepository: return "GitHub 仓库没填对：填 owner/仓库名，或完整链接"
        case .noRelease: return "GitHub 上还没有发布版本"
        case .transport(let message): return message
        case .http(403): return "GitHub 暂时拒绝访问（多半是匿名请求太频繁，过一小时再试）"
        case .http(404): return "GitHub 上找不到这个仓库的发布版本"
        case .http(let code): return "GitHub 返回 HTTP \(code)"
        }
    }
}

/// 去 GitHub Releases 对版本：启动与每隔几小时自动查一次，面板、右键菜单、设置里都能手动查
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published private(set) var status: UpdateStatus = .idle
    @Published private(set) var lastChecked: Date?

    static let defaultRepository = Preferences.defaultRepository
    /// 自动检查的间隔；一轮没结果也要等这么久再去问，别把匿名额度烧光
    private static let checkInterval: TimeInterval = 6 * 3600
    /// 轮询节律：到点才真的发请求
    private static let tickInterval: TimeInterval = 5 * 60

    private let prefs = Preferences.shared
    private var ticker: Task<Void, Never>?
    private var inFlight: Task<UpdateStatus, Never>?

    private nonisolated init() {}

    var latest: GitHubRelease? { status.release }

    /// 值得在面板上提示一句的版本：确实更新，且用户没说过"忽略这版"
    var bannerRelease: GitHubRelease? {
        guard let release = status.release, status.isUpdateAvailable else { return nil }
        return prefs.dismissedUpdateVersion == release.tagName ? nil : release
    }

    var hasUpdateHint: Bool { bannerRelease != nil }

    /// 设置里那个按钮的文案，正在查的时候别让人以为点下去没反应
    var checkingLabel: String {
        if case .checking = status { return "检查中…" }
        return "检查更新"
    }

    var repository: String { Self.repository(from: prefs.githubRepository) }

    /// 主页 / 发布页：仓库地址填成链接、`owner/repo`、甚至带.git 都能认
    static func repository(from raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: text), let host = url.host, host.contains("github.com") {
            text = url.path
        }
        if text.hasPrefix("/") { text.removeFirst() }
        if text.hasSuffix(".git") { text.removeLast(4) }
        if text.hasSuffix("/") { text.removeLast() }
        let pieces = text.split(separator: "/").map(String.init)
        guard pieces.count >= 2 else { return "" }
        return "\(pieces[pieces.count - 2])/\(pieces[pieces.count - 1])"
    }

    var homeURL: URL? {
        repository.isEmpty ? nil : URL(string: "https://github.com/\(repository)")
    }

    var releasesURL: URL? {
        repository.isEmpty ? nil : URL(string: "https://github.com/\(repository)/releases")
    }

    /// 始终能点开的"最新一版"链接，GitHub 会自己跳到最新的 tag 页
    var latestURL: URL? {
        bannerRelease?.pageURL ?? latest?.pageURL
            ?? (repository.isEmpty ? nil : URL(string: "https://github.com/\(repository)/releases/latest"))
    }

    func start() {
        restore()
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkIfDue()
                try? await Task.sleep(nanoseconds: UInt64(Self.tickInterval * 1_000_000_000))
            }
        }
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
    }

    func checkIfDue() async {
        guard prefs.autoCheckUpdates else { return }
        if let lastChecked, Date().timeIntervalSince(lastChecked) < Self.checkInterval { return }
        _ = await check()
    }

    /// 面板打开时也走这里：离上次检查没到间隔就直接返回缓存结果，不会每次都发请求
    @discardableResult
    func check() async -> UpdateStatus {
        if case .checking = status, let inFlight { return await inFlight.value }
        status = .checking
        let task = Task { [weak self] () -> UpdateStatus in
            guard let self else { return .failed("小工具已经退出") }
            do {
                let release = try await self.fetchLatest()
                return self.resolve(release)
            } catch {
                return .failed(error.localizedDescription)
            }
        }
        inFlight = task
        let result = await task.value
        inFlight = nil
        status = result
        lastChecked = Date()
        persist()
        return result
    }

    /// 用户点了"忽略这个版本"：同一个小版本号不再刷屏，出了更新的版本照常提示
    func dismiss(_ release: GitHubRelease) {
        prefs.dismissedUpdateVersion = release.tagName
        objectWillChange.send()
    }

    func resetDismiss() {
        prefs.dismissedUpdateVersion = ""
        objectWillChange.send()
    }

    private func resolve(_ release: GitHubRelease) -> UpdateStatus {
        guard let remote = release.version else { return .failed("版本号读不懂：\(release.tagName)") }
        let local = AppVersion.current
        if remote > local { return .available(release) }
        if remote < local { return .ahead(release) }
        return .upToDate
    }

    private func fetchLatest() async throws -> GitHubRelease {
        let repo = repository
        guard !repo.isEmpty else { throw UpdateError.noRepository }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        let session = URLSession(configuration: config)

        if let release = try? await request(session, "https://api.github.com/repos/\(repo)/releases/latest", as: GitHubRelease.self),
           release.draft != true {
            return release
        }
        // 只有预发布 / latest 接口出岔子时退到列表
        let list = try await request(session, "https://api.github.com/repos/\(repo)/releases?per_page=10", as: [GitHubRelease].self)
        guard let release = list.first(where: { $0.draft != true && $0.version != nil }) else {
            throw UpdateError.noRelease
        }
        return release
    }

    private func request<T: Decodable>(_ session: URLSession, _ address: String, as type: T.Type) async throws -> T {
        guard let url = URL(string: address) else { throw UpdateError.noRepository }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("omlx-widget/\(AppVersion.current)", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw UpdateError.http(0)
            }
            guard (200..<300).contains(http.statusCode) else {
                throw UpdateError.http(http.statusCode)
            }
            return try JSONDecoder().decode(T.self, from: data)
        } catch let error as UpdateError {
            throw error
        } catch let error as URLError {
            throw UpdateError.transport(OmlxClient.describe(error))
        } catch {
            throw UpdateError.transport("GitHub 响应解析失败：\(error.localizedDescription)")
        }
    }

    /// 更新说明：优先读安装包自带的 ReleaseNotes.md（离线也有、不占 GitHub 额度），
    /// 包里没有再退回 GitHub 上那条 Release 的正文
    func changelog(for release: GitHubRelease?) -> String {
        if let bundled = Self.bundledNotes() { return bundled }
        return ReleaseNotesParser.trim(release?.body ?? "")
    }

    private static func bundledNotes() -> String? {
        let names = ["ReleaseNotes", "RELEASE_NOTES"]
        for name in names {
            if let url = Bundle.main.url(forResource: name, withExtension: "md"),
               let text = try? String(contentsOf: url, encoding: .utf8),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return ReleaseNotesParser.trim(text)
            }
        }
        // 直接跑 .build 里的二进制时包外找：.build/x.app → 仓库根目录
        let root = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        for name in names {
            let candidate = root.appendingPathComponent("\(name).md")
            if let text = try? String(contentsOf: candidate, encoding: .utf8),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return ReleaseNotesParser.trim(text)
            }
        }
        return nil
    }

    private func persist() {
        prefs.lastUpdateCheck = lastChecked?.timeIntervalSince1970 ?? 0
        if let release = status.release, let data = try? JSONEncoder().encode(release) {
            prefs.lastReleaseData = data
        } else {
            prefs.lastReleaseData = Data()
        }
    }

    private func restore() {
        let stamp = prefs.lastUpdateCheck
        if stamp > 0 { lastChecked = Date(timeIntervalSince1970: stamp) }
        guard let release = try? JSONDecoder().decode(GitHubRelease.self, from: prefs.lastReleaseData),
              release.tagName.isEmpty == false else { return }
        status = resolve(release)
    }
}

/// 更新弹窗是为什么弹的：装完第一次启动、更新完第一次启动、还是用户手动点了"检查更新"
enum UpdatePresentation {
    case firstRun
    case upgraded(from: String)
    case checked
}

extension UpdateChecker {
    func report(for presentation: UpdatePresentation) -> UpdateReport {
        let local = AppVersion.current.description
        switch presentation {
        case .firstRun:
            return UpdateReport(
                headline: "欢迎使用 v\(local)",
                subline: "这一版的内容如下。以后每次更新完，第一次启动都会在这里讲清楚改了什么。",
                symbol: "sparkles",
                tint: Color.accentColor,
                notes: changelog(for: latest),
                downloadURL: status.isUpdateAvailable ? latestURL : nil,
                pageURL: releasesURL
            )
        case .upgraded(let previous):
            return UpdateReport(
                headline: "已更新到 v\(local)",
                subline: "上一版是 v\(previous)。下面是要紧的变化：",
                symbol: "arrow.down.circle",
                tint: Color.accentColor,
                notes: changelog(for: latest),
                downloadURL: status.isUpdateAvailable ? latestURL : nil,
                pageURL: releasesURL
            )
        case .checked:
            switch status {
            case .available(let release):
                var subline = "本机 v\(local)，GitHub 上是 \(release.tagName)"
                if let published = release.publishedText { subline += " · 发布于 \(published)" }
                return UpdateReport(
                    headline: "发现新版本 \(release.tagName)",
                    subline: subline,
                    symbol: "arrow.up.circle",
                    tint: Palette.kind(.loading),
                    notes: changelog(for: release),
                    downloadURL: release.downloadURL ?? latestURL,
                    pageURL: release.pageURL ?? releasesURL
                )
            case .ahead(let release):
                return UpdateReport(
                    headline: "本机 v\(local) 比 GitHub 上的更新",
                    subline: "GitHub 上最新是 \(release.tagName)：这是自己打的开发包，或者 CI 的 Release 还没建好",
                    symbol: "hare",
                    tint: Palette.kind(.loading),
                    notes: changelog(for: release),
                    downloadURL: nil,
                    pageURL: releasesURL
                )
            case .failed(let message):
                return UpdateReport(
                    headline: "没能问到 GitHub",
                    subline: message,
                    symbol: "wifi.slash",
                    tint: Palette.kind(.offline),
                    notes: changelog(for: nil),
                    downloadURL: releasesURL,
                    pageURL: homeURL
                )
            case .checking:
                return UpdateReport(
                    headline: "正在检查更新…",
                    subline: "GitHub api.github.com 还没回话",
                    symbol: "arrow.triangle.2.circlepath",
                    tint: Color.accentColor,
                    notes: changelog(for: nil),
                    downloadURL: nil,
                    pageURL: releasesURL
                )
            case .idle, .upToDate:
                var subline = "GitHub 上最新的发布版也是 v\(local)"
                subline += lastChecked == nil ? " · 下次启动再问一次" : " · 查于 \(Fmt.clock(lastChecked))"
                return UpdateReport(
                    headline: "已经是最新版 v\(local)",
                    subline: subline,
                    symbol: "checkmark.seal",
                    tint: Palette.kind(.busy),
                    notes: changelog(for: nil),
                    downloadURL: nil,
                    pageURL: releasesURL
                )
            }
        }
    }
}
