import Foundation

enum OmlxError: LocalizedError {
    case invalidURL(String)
    case http(Int, String)
    /// 401 / 403：oMLX 开了鉴权，key 没填或者不对，和"连不上"是两回事
    case auth(Int, String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let raw): return "地址无法解析：\(raw)"
        case .http(let code, let body): return "HTTP \(code) \(body.prefix(120))"
        case .auth(let code, _): return "oMLX 要求 API Key（HTTP \(code)）"
        case .transport(let message): return message
        }
    }

    /// 面板据此决定是催用户填 key，还是照常提示隧道 / 服务没起
    var requiresAPIKey: Bool {
        if case .auth = self { return true }
        return false
    }
}

struct OmlxClient {
    var baseURL: URL
    var apiKey: String
    var session: URLSession

    init(baseURL: URL, apiKey: String = "", timeout: TimeInterval = 6) {
        self.baseURL = baseURL
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout + 4
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        self.session = URLSession(configuration: config)
    }

    func url(for path: String, query: [String: String] = [:]) -> URL? {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            return nil
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url
    }

    @discardableResult
    func raw(_ path: String, query: [String: String] = [:], method: String = "GET", body: Data? = nil) async throws -> (Data, TimeInterval) {
        guard let target = url(for: path, query: query) else {
            throw OmlxError.invalidURL(path)
        }
        var request = URLRequest(url: target)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let started = Date()
        do {
            let (data, response) = try await session.data(for: request)
            let latency = Date().timeIntervalSince(started)
            guard let http = response as? HTTPURLResponse else {
                throw OmlxError.transport("响应缺少 HTTP 层")
            }
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data.prefix(400), encoding: .utf8) ?? ""
                if http.statusCode == 401 || http.statusCode == 403 {
                    throw OmlxError.auth(http.statusCode, body)
                }
                throw OmlxError.http(http.statusCode, body)
            }
            return (data, latency)
        } catch let error as OmlxError {
            throw error
        } catch let error as URLError {
            throw OmlxError.transport(Self.describe(error))
        }
    }

    func get<T: Decodable>(_ type: T.Type, _ path: String, query: [String: String] = [:]) async throws -> (T, TimeInterval) {
        let (data, latency) = try await raw(path, query: query)
        do {
            return (try JSONDecoder().decode(T.self, from: data), latency)
        } catch {
            throw OmlxError.transport("解析失败 \(path): \(error.localizedDescription)")
        }
    }

    func getOptional<T: Decodable>(_ type: T.Type, _ path: String, query: [String: String] = [:]) async -> (T?, TimeInterval) {
        do {
            let (value, latency) = try await get(type, path, query: query)
            return (value, latency)
        } catch {
            return (nil, 0)
        }
    }

    static func describe(_ error: URLError) -> String {
        switch error.code {
        case .cannotConnectToHost: return "连不上服务器（SSH 隧道是否已启动？）"
        case .timedOut: return "请求超时"
        case .cannotFindHost: return "找不到主机"
        case .networkConnectionLost: return "连接中断"
        case .notConnectedToInternet: return "网络未连接"
        default: return error.localizedDescription
        }
    }
}
