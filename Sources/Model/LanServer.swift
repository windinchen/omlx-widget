import Foundation
import Combine
import Network

/// 小工具自带的局域网服务：手机 / 别的电脑用浏览器打开就能看同一份实时数据。
/// 只服务自己那几个路由，手写几十行 HTTP/1.1，不为一个页面引入第三方依赖
/// 可变状态只在那条串行 queue 上读写，@Published 那三个只在主线程改，
/// 两边的交接都走 dispatch，所以按 unchecked Sendable 上报
final class LanServer: ObservableObject, @unchecked Sendable {
    static let shared = LanServer()

    enum Status: Equatable {
        case stopped
        case starting
        case running(UInt16)
        case failed(String)

        var port: UInt16? {
            if case .running(let port) = self { return port }
            return nil
        }

        var label: String {
            switch self {
            case .stopped: return "未启用"
            case .starting: return "正在启动…"
            case .running(let port): return "监听中 · 端口 \(port)"
            case .failed(let reason): return "启动失败：\(reason)"
            }
        }
    }

    @Published private(set) var status: Status = .stopped
    /// 有没有真的有人连进来：系统防火墙把入站连接拦掉时，这里一直是 0 就是最好的线索
    @Published private(set) var hits = 0
    @Published private(set) var lastHitAt: Date?

    private let queue = DispatchQueue(label: "local.omlx-widget.lan", qos: .utility)
    private var listener: NWListener?
    /// 下面三个值只在 queue 上读写，主线程要看得走 publish
    private var boundPort: UInt16?
    private var wantedKey = ""

    private init() {}

    // MARK: - 生命周期

    /// 设置里的开关 / 端口 / 口令改动都汇到这里：没变就什么都不做，变了才重建监听
    func apply(enabled: Bool, port: Int, key: String) {
        queue.async {
            guard enabled else {
                self.stopLocked()
                return
            }
            let wanted = UInt16(clamping: min(max(port, 1), 65_535))
            self.wantedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if self.boundPort == wanted { return }
            self.stopLocked()
            self.publish { self.status = .starting }
            self.bindLocked(port: wanted, retriesLeft: 8)
        }
    }

    func stop() {
        queue.async { self.stopLocked() }
    }

    /// 设置页与右键菜单都要展示的分享地址；未监听时给空，界面就不画那一块
    @MainActor var shareURLs: [URL] {
        guard let port = status.port else { return [] }
        // wantedKey 只在 queue 上写，这里取一次快照再拼字符串；queue 从不反过来等主线程，sync 不会互锁
        let key = queue.sync { self.wantedKey }
        return LanAddress.current().prefix(4).map { item in
            var text = "http://\(item.address):\(port)/"
            if !key.isEmpty { text += "?key=\(key)" }
            return URL(string: text) ?? URL(string: "http://127.0.0.1:\(port)/")!
        }
    }

    @MainActor var firstShareURLText: String? { shareURLs.first?.absoluteString }

    private func bindLocked(port: UInt16, retriesLeft: Int) {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        guard let endpoint = NWEndpoint.Port(rawValue: port) else {
            publish { self.status = .failed("端口 \(port) 不能用") }
            return
        }
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: endpoint)
        } catch {
            failOrRetryLocked(port: port, retriesLeft: retriesLeft, error: error)
            return
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.queue.async {
                    self.boundPort = port
                    self.publish { self.status = .running(port) }
                }
            case .failed(let error):
                self.queue.async {
                    guard self.listener === listener else { return }
                    listener.stateUpdateHandler = nil
                    listener.cancel()
                    self.listener = nil
                    self.boundPort = nil
                    self.failOrRetryLocked(port: port, retriesLeft: retriesLeft, error: error)
                }
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.queue.async { self?.receive(from: connection) }
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    /// 端口被人占了就往上找一个，最多试 8 个；设置页显示实际监听端口
    private func failOrRetryLocked(port: UInt16, retriesLeft: Int, error: Error) {
        guard retriesLeft > 0 else {
            publish { self.status = .failed(Self.describe(error)) }
            return
        }
        self.bindLocked(port: port &+ 1, retriesLeft: retriesLeft - 1)
    }

    private func stopLocked() {
        listener?.stateUpdateHandler = nil
        listener?.cancel()
        listener = nil
        boundPort = nil
        publish { self.status = .stopped }
    }

    private func publish(_ change: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async { change() }
    }

    private static func describe(_ error: Error) -> String {
        if case NWError.posix(let code) = error, code == .EADDRINUSE {
            return "端口已被占用，试了 8 个都连不上"
        }
        return error.localizedDescription
    }

    // MARK: - 连接

    private func receive(from connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            if case .failed = state { connection.cancel() }
        }
        connection.start(queue: queue)
        read(from: connection, buffer: Data(), rounds: 0)
    }

    private func read(from connection: NWConnection, buffer: Data, rounds: Int) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] chunk, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            self.queue.async {
                var gathered = buffer
                if let chunk { gathered.append(chunk) }
                if let request = LanRequest.parse(gathered) {
                    self.handle(request, from: connection)
                    return
                }
                guard error == nil, !isComplete, rounds < 24 else {
                    connection.cancel()
                    return
                }
                self.read(from: connection, buffer: gathered, rounds: rounds + 1)
            }
        }
    }

    private func handle(_ request: LanRequest, from connection: NWConnection) {
        publish {
            self.hits += 1
            self.lastHitAt = Date()
        }
        switch request.path {
        case "/", "/index.html":
            respond(connection, status: 200, type: "text/html; charset=utf-8", body: Data(LanDashboard.html.utf8))
        case "/favicon.ico":
            respond(connection, status: 204, type: "text/plain", body: Data())
        case "/api/snapshot":
            guard authorized(request, from: connection) else { return }
            Task { [weak self] in
                let body = await LanServer.snapshotBody()
                self?.queue.async {
                    self?.respond(connection, status: 200, type: "application/json; charset=utf-8", body: body)
                }
            }
        case "/api/action":
            guard authorized(request, from: connection) else { return }
            Task { [weak self] in
                let message = await LanCommand.run(request.bodyText)
                let body = (try? JSONSerialization.data(withJSONObject: ["ok": true, "message": message])) ?? Data()
                self?.queue.async {
                    self?.respond(connection, status: 200, type: "application/json; charset=utf-8", body: body)
                }
            }
        default:
            respond(connection, status: 404, type: "application/json; charset=utf-8",
                    body: Data(#"{"ok":false,"error":"没有这个地址"}"#.utf8))
        }
    }

    /// 填了口令才校验；页面本身照常发出去，缺口令时由页面弹输入框，比服务端跳登录页省事
    private func authorized(_ request: LanRequest, from connection: NWConnection) -> Bool {
        guard !wantedKey.isEmpty else { return true }
        if request.query("key") == wantedKey { return true }
        respond(connection, status: 401, type: "application/json; charset=utf-8",
                body: Data(#"{"ok":false,"error":"需要访问口令","auth":true}"#.utf8))
        return false
    }

    private func respond(_ connection: NWConnection, status: Int, type: String, body: Data) {
        var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
        if status == 204 {
            head += "Connection: close\r\n\r\n"
        } else {
            head += "Content-Type: \(type)\r\n"
            head += "Content-Length: \(body.count)\r\n"
            head += "Cache-Control: no-store\r\n"
            head += "Connection: close\r\n\r\n"
        }
        var payload = Data(head.utf8)
        payload.append(body)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 204: return "No Content"
        case 401: return "Unauthorized"
        default: return "Not Found"
        }
    }

    private static func snapshotBody() async -> Data {
        await MainActor.run {
            (try? JSONEncoder().encode(WidgetState.shared.lanSnapshot())) ?? Data("{}".utf8)
        }
    }
}

/// 网页发来的一个动作：刷新 / 测速 / 加载或卸载某个模型
enum LanCommand {
    static func run(_ body: String) async -> String {
        let payload = Self.decode(body)
        let state = WidgetState.shared
        switch payload?["action"] as? String {
        case "probe":
            await state.runSpeedProbe()
            let notice = await state.notice
            return notice ?? "测速请求已完成"
        case "toggle":
            guard let id = payload?["id"] as? String else { return "缺少模型名" }
            let loaded = payload?["loaded"] as? Bool ?? false
            await state.toggleModel(id: id, loaded: loaded)
            return loaded ? "已发起卸载 \(id)" : "已发起加载 \(id)"
        default:
            await state.refresh()
            return "已刷新"
        }
    }

    private static func decode(_ body: String) -> [String: Any]? {
        guard let data = body.data(using: .utf8), !data.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

/// 一条解析好的 HTTP 请求。只需要 GET / POST、一个查询串和一小段 JSON body，
/// 所以不去拆完整的 RFC，缺的东西一律按「用不上」处理
struct LanRequest {
    var method: String
    var path: String
    private var query: [String: String]
    var bodyText: String

    func query(_ name: String) -> String? { query[name] }

    static func parse(_ data: Data) -> LanRequest? {
        guard let text = String(data: data, encoding: .utf8),
              let split = text.range(of: "\r\n\r\n") else { return nil }
        let head = String(text[..<split.lowerBound])
        let lines = head.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let pieces = requestLine.split(separator: " ")
        guard pieces.count >= 2 else { return nil }
        let method = String(pieces[0]).uppercased()
        var path = String(pieces[1])
        var query: [String: String] = [:]
        if let mark = path.firstIndex(of: "?") {
            for pair in path[path.index(after: mark)...].split(separator: "&") {
                let parts = pair.split(separator: "=", maxSplits: 1)
                let name = String(parts[0]).removingPercentEncoding ?? String(parts[0])
                let value = parts.count > 1 ? (String(parts[1]).removingPercentEncoding ?? String(parts[1])) : ""
                query[name] = value
            }
            path = String(path[..<mark])
        }
        let body = String(text[split.upperBound...])
        let needed = lines.compactMap { line -> Int? in
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, parts[0].lowercased() == "content-length" else { return nil }
            return Int(parts[1].trimmingCharacters(in: .whitespaces))
        }.first ?? 0
        guard (body.data(using: .utf8)?.count ?? 0) >= needed else { return nil }
        return LanRequest(method: method, path: path, query: query, bodyText: body)
    }
}

/// 本机可以拿来访问的地址：跳过 loopback 与 169.254 自动私有地址，
/// 私网段排在前面，VPN / Tailscale 那种隧道地址也列出来但排在后面
enum LanAddress {
    struct Item: Hashable {
        var interface: String
        var address: String
    }

    static func current() -> [Item] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return [] }
        defer { freeifaddrs(first) }
        var found: [Item] = []
        var cursor = first
        while let entry = cursor {
            let next = entry.pointee.ifa_next
            if let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: entry.pointee.ifa_name)
                var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                var storage = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_in.self).pointee
                if let printed = inet_ntop(AF_INET, &storage.sin_addr, &text, socklen_t(text.count)) {
                    let address = String(cString: printed)
                    if isInetAddress(address) {
                        found.append(Item(interface: name, address: address))
                    }
                }
            }
            cursor = next
        }
        return Array(Set(found).sorted {
            let left = rank($0)
            let right = rank($1)
            return left == right ? $0.address.localizedStandardCompare($1.address) == .orderedAscending : left < right
        }.prefix(6))
    }

    private static func isInetAddress(_ address: String) -> Bool {
        !address.hasPrefix("127.") && !address.hasPrefix("169.254.") && address != "0.0.0.0"
    }

    /// 0 = 局域网 / 运营商内网段，1 = Tailscale 这类 CGNAT，2 = 其余公网地址
    private static func rank(_ item: Item) -> Int {
        if item.address.hasPrefix("10.") || item.address.hasPrefix("192.168.") || item.address.hasPrefix("172.") {
            return 0
        }
        if item.address.hasPrefix("100.64.") || item.interface.hasPrefix("utun") { return 1 }
        return 2
    }
}
