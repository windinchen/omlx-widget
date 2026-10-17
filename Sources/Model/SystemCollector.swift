import Foundation

enum ThermalLevel: Int, Comparable {
    case unknown = 0
    case nominal
    case fair
    case serious
    case critical

    var label: String {
        switch self {
        case .unknown: return "未知"
        case .nominal: return "正常"
        case .fair: return "偏热"
        case .serious: return "很热"
        case .critical: return "过热"
        }
    }

    var systemImage: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .nominal: return "thermometer.low"
        case .fair: return "thermometer.medium"
        case .serious: return "thermometer.high"
        case .critical: return "exclamationmark.triangle"
        }
    }

    static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    static func from(name: String?) -> ThermalLevel {
        switch name?.lowercased() {
        case "nominal": return .nominal
        case "fair": return .fair
        case "serious": return .serious
        case "critical": return .critical
        default: return .unknown
        }
    }

    static func from(speedLimit: Double?) -> ThermalLevel {
        guard let limit = speedLimit else { return .unknown }
        if limit >= 99 { return .nominal }
        if limit >= 85 { return .fair }
        if limit >= 70 { return .serious }
        return .critical
    }
}

struct SystemSnapshot {
    var date = Date()
    var gpuDevice: Double?
    var gpuRenderer: Double?
    var gpuTiler: Double?
    var gpuMemoryInUse: Int64?
    var cpuBusy: Double?
    var load1: Double?
    var load5: Double?
    var load15: Double?
    var thermal: ThermalLevel = .unknown
    var cpuSpeedLimit: Double?
    var temperatureCPU: Double?
    var temperatureGPU: Double?
    var temperatureMax: Double?
    var powerTotal: Double?
    var powerCPU: Double?
    var powerGPU: Double?
    var coreCount: Int?
    var fanRPM: Double?
    var fanMaxRPM: Double?
    var cpuFreqMHz: Double?
    var gpuFreqMHz: Double?
    var ramUsage: Int64?
    var ramTotal: Int64?
    var macmonReady = false
    /// 这一帧数据是本地采的还是 SSH 采的，面板要标出来
    var source: SystemSource = .ssh
    var error: String?

    var gpuFraction: Double { min(1, max(0, (gpuDevice ?? 0) / 100)) }

    var fanFraction: Double? {
        guard let rpm = fanRPM, let ceiling = fanMaxRPM, ceiling > 0 else { return nil }
        return min(1, max(0, rpm / ceiling))
    }

    var hasAnyValue: Bool {
        gpuDevice != nil || gpuRenderer != nil || cpuBusy != nil || load1 != nil
            || temperatureCPU != nil || temperatureMax != nil || powerTotal != nil
    }

    var peakTemperature: Double? {
        if let max = temperatureMax { return max }
        return max(temperatureCPU ?? -1, temperatureGPU ?? -1).nonNegative
    }

    var thermalDisplay: ThermalLevel {
        if thermal != .unknown { return thermal }
        if let peak = peakTemperature {
            if peak >= 95 { return .critical }
            if peak >= 88 { return .serious }
            if peak >= 78 { return .fair }
            return .nominal
        }
        return ThermalLevel.from(speedLimit: cpuSpeedLimit)
    }
}

private extension Double {
    var nonNegative: Double? { self < 0 ? nil : self }
}

/// 系统指标从哪儿采的：采集目标就是这台机器时直接本地跑命令，否则走 SSH
enum SystemSource: String {
    case local
    case ssh

    var isLocal: Bool { self == .local }
}

/// 判断一个采集目标是不是"这台机器自己"：loopback、本机主机名、以及本机任一网卡地址。
/// 小工具跑在 oMLX 那台主机上时不必开远程登录、也不用给自己配免密
enum LocalHost {
    /// user@host:port / http://host:port / [IPv6]:port → 纯主机名（小写）
    static func normalize(_ target: String) -> String {
        var host = target.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let scheme = host.range(of: "://") { host = String(host[scheme.upperBound...]) }
        if let slash = host.firstIndex(of: "/") { host = String(host[host.startIndex..<slash]) }
        if let at = host.lastIndex(of: "@") { host = String(host[host.index(after: at)...]) }
        if host.hasPrefix("[") {
            if let close = host.firstIndex(of: "]") {
                host = String(host[host.index(after: host.startIndex)..<close])
            }
        } else if host.filter({ $0 == ":" }).count == 1, let colon = host.lastIndex(of: ":") {
            host = String(host[host.startIndex..<colon])
        }
        return host
    }

    static func isLocal(_ target: String) -> Bool {
        let host = normalize(target)
        guard !host.isEmpty else { return false }
        return identities.contains(host)
    }

    private static var identities: Set<String> {
        var set: Set<String> = ["localhost", "127.0.0.1", "0.0.0.0", "::1", "ip6-localhost", "ip6-loopback"]
        var nameBuffer = [CChar](repeating: 0, count: 256)
        if gethostname(&nameBuffer, nameBuffer.count) == 0 {
            let host = String(cString: nameBuffer).lowercased()
            if !host.isEmpty {
                set.insert(host)
                if let dot = host.firstIndex(of: ".") { set.insert(String(host[..<dot])) }
                if host.hasSuffix(".local") { set.insert(String(host.dropLast(6))) }
            }
        }
        set.formUnion(interfaceAddresses())
        return set
    }

    private static func interfaceAddresses() -> Set<String> {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return [] }
        defer { freeifaddrs(first) }
        var addresses: Set<String> = []
        var cursor = first
        while let entry = cursor {
            let next = entry.pointee.ifa_next
            if let address = entry.pointee.ifa_addr {
                let raw = UnsafeRawPointer(address)
                var text = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                let printed: UnsafePointer<CChar>?
                if address.pointee.sa_family == UInt8(AF_INET) {
                    var storage = raw.assumingMemoryBound(to: sockaddr_in.self).pointee
                    printed = inet_ntop(AF_INET, &storage.sin_addr, &text, socklen_t(text.count))
                } else if address.pointee.sa_family == UInt8(AF_INET6) {
                    var storage = raw.assumingMemoryBound(to: sockaddr_in6.self).pointee
                    printed = inet_ntop(AF_INET6, &storage.sin6_addr, &text, socklen_t(text.count))
                } else {
                    printed = nil
                }
                if let printed {
                    var name = String(cString: printed)
                    if let percent = name.firstIndex(of: "%") { name = String(name[..<percent]) }
                    if !name.isEmpty { addresses.insert(name.lowercased()) }
                }
            }
            cursor = next
        }
        return addresses
    }
}

/// 通过 SSH 在远端跑几条零权限命令采集 GPU / CPU / 温度。
/// macOS 26 上 AppleSMC 用户客户端对非 root 关闭了读取，数字温度依赖 macmon（sudoless）。
final class SystemCollector {
    nonisolated(unsafe) static let shared = SystemCollector()

    private init() {}

    private static let markers = ["@IOREG", "@LOAD", "@IOSTAT", "@CORES", "@THERM", "@MON"]

    private static let remoteScript = """
    echo "@IOREG"; ioreg -rd1 -c IOAccelerator 2>/dev/null | tr , "\\n" | grep -E "Utilization %|In use system memory"; \
    echo "@LOAD"; sysctl -n vm.loadavg 2>/dev/null; \
    echo "@CORES"; sysctl -n hw.ncpu 2>/dev/null; \
    echo "@IOSTAT"; iostat -c 2 -w 1 2>/dev/null | tail -1; \
    echo "@THERM"; pmset -g therm 2>&1 | tail -6; \
    echo "@MON"; \
    if [ -x /opt/homebrew/bin/macmon ]; then /opt/homebrew/bin/macmon pipe -s 1 -i 900 2>/dev/null | head -n 1; elif [ -x /usr/local/bin/macmon ]; then /usr/local/bin/macmon pipe -s 1 -i 900 2>/dev/null | head -n 1; else echo \"@NOMON\"; fi; \
    echo "@END"
    """

    /// fast = true 时跳过 iostat（macmon 已经给了 CPU 占用），一次采集约 2 秒。
    /// 采集目标就是这台机器（loopback / 本机主机名 / 本机网卡地址）时直接在本地执行
    /// 同一套命令；SSH 目标留空时按 oMLX 服务器地址判断，同样是自己就本地采
    func sample(
        target: String,
        serverHost: String = "",
        mode: SystemSourceChoice = .auto,
        fast: Bool = false,
        timeout: TimeInterval = 9
    ) async -> SystemSnapshot {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        let source: SystemSource
        switch mode {
        case .local:
            source = .local
        case .remote:
            guard !trimmed.isEmpty else {
                var snapshot = SystemSnapshot()
                snapshot.error = "未配置 SSH 地址"
                return snapshot
            }
            source = .ssh
        case .auto:
            if LocalHost.isLocal(trimmed) {
                source = .local
            } else if trimmed.isEmpty {
                guard LocalHost.isLocal(serverHost) else {
                    var snapshot = SystemSnapshot()
                    snapshot.error = "未配置 SSH 地址"
                    return snapshot
                }
                source = .local
            } else {
                source = .ssh
            }
        }
        let script = fast ? SystemCollector.fastScript : SystemCollector.remoteScript
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let snapshot = source.isLocal
                    ? SystemCollector.runLocal(script: script, timeout: min(timeout, 6))
                    : SystemCollector.run(target: trimmed, script: script, timeout: timeout)
                continuation.resume(returning: snapshot)
            }
        }
    }

    private static let fastScript = """
    echo "@IOREG"; ioreg -rd1 -c IOAccelerator 2>/dev/null | tr , "\\n" | grep -E "Utilization %|In use system memory"; \
    echo "@CORES"; sysctl -n hw.ncpu 2>/dev/null; \
    echo "@THERM"; pmset -g therm 2>&1 | tail -6; \
    echo "@MON"; \
    if [ -x /opt/homebrew/bin/macmon ]; then /opt/homebrew/bin/macmon pipe -s 1 -i 500 2>/dev/null | head -n 1; elif [ -x /usr/local/bin/macmon ]; then /usr/local/bin/macmon pipe -s 1 -i 500 2>/dev/null | head -n 1; else echo \"@NOMON\"; fi; \
    echo "@END"
    """

    private static func run(target: String, script: String, timeout: TimeInterval) -> SystemSnapshot {
        var arguments = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5",
            "-o", "ControlMaster=auto",
            "-o", "ControlPath=\(NSHomeDirectory())/.ssh/cm-omlx-widget-%r@%h:%p",
            "-o", "ControlPersist=300",
            "-o", "ServerAliveInterval=5",
            "-o", "LogLevel=ERROR",
        ]
        arguments.append(target)
        arguments.append(script)
        return execute(
            executable: "/usr/bin/ssh",
            arguments: arguments,
            timeout: timeout,
            source: .ssh,
            failureHint: "远端未返回可用指标"
        )
    }

    /// 目标就是本机时走这里：同一套命令本地执行，不碰 SSH 也不要求远程登录
    private static func runLocal(script: String, timeout: TimeInterval) -> SystemSnapshot {
        execute(
            executable: "/bin/sh",
            arguments: ["-c", script],
            timeout: timeout,
            source: .local,
            failureHint: "本机没返回可用指标（GPU 占用靠 ioreg，数字温度要 macmon）"
        )
    }

    private static func execute(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        source: SystemSource,
        failureHint: String
    ) -> SystemSnapshot {
        let path = NSTemporaryDirectory() + "omlx-sys-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString).txt"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment

        FileManager.default.createFile(atPath: path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: path) else {
            var snapshot = SystemSnapshot()
            snapshot.source = source
            snapshot.error = "无法写入临时文件"
            return snapshot
        }
        process.standardOutput = handle
        process.standardError = FileHandle.nullDevice

        let watchdog = DispatchWorkItem {
            if process.isRunning {
                process.interrupt()
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) {
                    if process.isRunning { process.terminate() }
                }
            }
        }

        var snapshot = SystemSnapshot()
        snapshot.source = source
        do {
            try process.run()
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
            process.waitUntilExit()
            watchdog.cancel()
            handle.closeFile()
            let data = (try? Data(contentsOf: URL(fileURLWithPath: path))) ?? Data()
            let text = String(data: data, encoding: .utf8) ?? ""
            snapshot = parse(text)
            snapshot.source = source
            if !snapshot.hasAnyValue {
                if source == .ssh && process.terminationStatus == 255 {
                    snapshot.error = "SSH 连接失败（检查免密登录与地址）"
                } else {
                    snapshot.error = failureHint
                }
            }
        } catch {
            snapshot.error = "无法启动 \(URL(fileURLWithPath: executable).lastPathComponent)：\(error.localizedDescription)"
        }
        try? FileManager.default.removeItem(atPath: path)
        return snapshot
    }

    // MARK: - Parsing

    static func parse(_ text: String) -> SystemSnapshot {
        var snapshot = SystemSnapshot()
        var section = ""
        var monLines: [String] = []
        var sawMacmon = false

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if markers.contains(line) {
                section = String(line.dropFirst())
                if section == "NOMON" { sawMacmon = false }
                continue
            }
            switch section {
            case "IOREG": parseAccelerator(line, &snapshot)
            case "LOAD": parseLoadAverage(line, &snapshot)
            case "CORES": if let count = Double(line) { snapshot.coreCount = Int(count) }
            case "IOSTAT": parseIostat(line, &snapshot)
            case "THERM": parseThermal(line, &snapshot)
            case "MON": monLines.append(line)
            default: break
            }
        }

        for line in monLines where line.hasPrefix("{") {
            if parseMacmon(line, &snapshot) { sawMacmon = true }
        }
        snapshot.macmonReady = sawMacmon
        return snapshot
    }

    private static func parseAccelerator(_ line: String, _ snapshot: inout SystemSnapshot) {
        if let value = number(forKey: "\"Device Utilization %\"", in: line) { snapshot.gpuDevice = value }
        if let value = number(forKey: "\"Renderer Utilization %\"", in: line) { snapshot.gpuRenderer = value }
        if let value = number(forKey: "\"Tiler Utilization %\"", in: line) { snapshot.gpuTiler = value }
        if let value = number(forKey: "\"In use system memory\"", in: line) { snapshot.gpuMemoryInUse = Int64(value) }
    }

    private static func parseLoadAverage(_ line: String, _ snapshot: inout SystemSnapshot) {
        let numbers = line.split(whereSeparator: { "(), \t".contains($0) }).compactMap { Double($0) }
        guard numbers.count >= 3 else { return }
        snapshot.load1 = numbers[0]
        snapshot.load5 = numbers[1]
        snapshot.load15 = numbers[2]
    }

    private static func parseIostat(_ line: String, _ snapshot: inout SystemSnapshot) {
        let numbers = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).compactMap { Double($0) }
        guard numbers.count >= 6 else { return }
        let tail = Array(numbers.suffix(6))
        snapshot.cpuBusy = max(0, min(100, tail[0] + tail[1]))
        snapshot.load1 = tail[3]
        snapshot.load5 = tail[4]
        snapshot.load15 = tail[5]
    }

    private static func parseThermal(_ line: String, _ snapshot: inout SystemSnapshot) {
        if let limit = number(forKey: "CPU_Speed_Limit", in: line) {
            snapshot.cpuSpeedLimit = limit
            snapshot.thermal = max(snapshot.thermal, ThermalLevel.from(speedLimit: limit))
        }
        if line.lowercased().contains("thermal warning level") && !line.contains("=") {
            if snapshot.thermal == .unknown { snapshot.thermal = .nominal }
        }
    }

    @discardableResult
    private static func parseMacmon(_ line: String, _ snapshot: inout SystemSnapshot) -> Bool {
        guard let data = line.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              !root.isEmpty else { return false }

        if let temp = root["temp"] as? [String: Any] {
            snapshot.temperatureCPU = scalar(temp["cpu_temp_avg"])
            snapshot.temperatureGPU = scalar(temp["gpu_temp_avg"])
        }
        let knownTemps = [snapshot.temperatureCPU, snapshot.temperatureGPU].compactMap { $0 }
        if let peak = knownTemps.max() { snapshot.temperatureMax = peak }

        snapshot.powerTotal = scalar(root["sys_power"]) ?? scalar(root["all_power"])
        snapshot.powerCPU = scalar(root["cpu_power"])
        snapshot.powerGPU = scalar(root["gpu_power"])
        snapshot.cpuFreqMHz = max(scalar(root["pcpu_freq_mhz"]) ?? 0, scalar(root["ecpu_freq_mhz"]) ?? 0)
        snapshot.gpuFreqMHz = scalar(root["gpu_freq_mhz"])
        if snapshot.cpuBusy == nil { snapshot.cpuBusy = ratioToPercent(root["cpu_active_ratio"]) }
        if snapshot.gpuDevice == nil { snapshot.gpuDevice = ratioToPercent(root["gpu_active_ratio"]) }

        if let memory = root["memory"] as? [String: Any] {
            snapshot.ramUsage = Int64(scalar(memory["ram_usage"]) ?? 0)
            snapshot.ramTotal = Int64(scalar(memory["ram_total"]) ?? 0)
        }

        if let fans = root["fans"] as? [[String: Any]] {
            let sorted = fans.sorted { (scalar($0["rpm"]) ?? 0) > (scalar($1["rpm"]) ?? 0) }
            if let loudest = sorted.first {
                snapshot.fanRPM = scalar(loudest["rpm"])
                snapshot.fanMaxRPM = scalar(loudest["max_rpm"])
            }
        }
        return true
    }

    private static func scalar(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }

    private static func ratioToPercent(_ value: Any?) -> Double? {
        guard let value = scalar(value) else { return nil }
        return value <= 1.0 ? value * 100 : value
    }

    private static func number(forKey key: String, in text: String) -> Double? {
        guard let found = text.range(of: key) else { return nil }
        var digits = ""
        var seenDot = false
        for character in text[found.upperBound...] {
            if character == " " || character == "\t" || character == "=" || character == ":" {
                if digits.isEmpty { continue } else { break }
            }
            if character.isNumber {
                digits.append(character)
            } else if character == "." && !seenDot {
                digits.append(".")
                seenDot = true
            } else {
                break
            }
        }
        return Double(digits)
    }
}
