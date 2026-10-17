import Foundation
import Combine

enum WidgetKind {
    case offline
    case idle
    case busy
    case loading

    var label: String {
        switch self {
        case .offline: return "离线"
        case .idle: return "待命"
        case .busy: return "推理中"
        case .loading: return "加载中"
        }
    }
}

struct CompletionResponse: Codable {
    struct Usage: Codable {
        var promptTokens: Int?
        var completionTokens: Int?
        var totalTokens: Int?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }

    var usage: Usage?
    var model: String?
}

/// 一条任务的速度曲线：与服务端轮询同一时间轴对齐，按请求 ID 分组
struct TaskSeries: Identifiable, Equatable {
    var id: String
    var colorIndex: Int
    var values: [Double]
    var latest: Double
    /// 这一次轮询里这条任务还在不在吐字：决定它是否算"进行中的任务"
    var isLive: Bool
}

@MainActor
final class WidgetState: ObservableObject {
    nonisolated(unsafe) static let shared = WidgetState()

    @Published private(set) var status: ServerStatus?
    @Published private(set) var activity: ActivityResponse?
    @Published private(set) var usageToday: UsageResponse?
    @Published private(set) var usageWeek: UsageResponse?
    @Published private(set) var modelList: ModelStatusList?
    @Published private(set) var isOnline = false
    @Published private(set) var latencyMillis: Double?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var liveTps: Double = 0
    @Published private(set) var prefillTps: Double = 0
    @Published private(set) var tpsSeries: [Double] = []
    @Published private(set) var taskSeries: [TaskSeries] = []
    @Published private(set) var inflight: [GeneratingRequest] = []
    @Published private(set) var prefilling: [InflightRequest] = []
    @Published private(set) var isBusy = false
    @Published private(set) var kind: WidgetKind = .offline
    @Published private(set) var heatmap: [Int] = Array(repeating: 0, count: 24)
    @Published private(set) var menuBarTitle = ""
    @Published private(set) var serverName = Preferences.defaultServer.name
    @Published var notice: String?
    @Published private(set) var pendingModelID: String?
    @Published private(set) var probing = false
    @Published private(set) var system: SystemSnapshot?

    private struct Counter {
        var date: Date
        var completion: Int
        var freshPrompt: Int
    }

    private let prefs = Preferences.shared
    private var loop: Task<Void, Never>?
    private var systemLoop: Task<Void, Never>?
    private var systemCollecting = false
    /// 每个轮询点上的「请求 ID → tokens/s」，与 tpsSeries 一一对应
    private var taskSamples: [[String: Double]] = []
    /// 任务首次出现的顺序，决定配色；滑出曲线窗口后丢弃
    private var taskOrder: [String] = []
    /// 请求 ID → 配色序号。配色跟着任务走，任务活着期间不变色
    private var taskColors: [String: Int] = [:]
    private var counter: Counter?
    private var countersReset = false
    private var decayedTps = 0.0
    private var prefillAverage = 0.0
    private var lastBusyAt: Date?
    /// 采样空窗的保持时长：oMLX 的每请求速度是间歇回报的，这么多久没采到不算停，
    /// 沿用上一个值让稳定吐字画成一段高原；超过这个空窗才开始降档
    private static let sampleHoldSeconds = 8.0
    private var lastSlowPoll: Date?
    private var trackedServer: UUID?
    private var cancellables = Set<AnyCancellable>()

    private nonisolated init() {}

    var models: [ModelEntry] { modelList?.models ?? [] }
    var liveModels: [ModelActivity] { activity?.activeModels?.models ?? [] }
    var isPrefilling: Bool { !prefilling.isEmpty }
    var prefillFraction: Double? { prefilling.compactMap { $0.progress }.max() }
    var prefillSpeed: Double { prefilling.compactMap { $0.estimatedSpeed }.max() ?? prefillTps }
    /// 两条及以上任务同时在吐字时才改用多色曲线，单任务保持原来的单条曲线
    var showsTaskCurves: Bool { liveTaskSeries.count >= 2 }
    /// 仍在吐字的任务，图例只列这些，已结束的不占图例位
    var liveTaskSeries: [TaskSeries] { taskSeries.filter { $0.isLive } }

    func taskColorIndex(forRequestId id: String?) -> Int? {
        guard let id else { return nil }
        return taskSeries.first(where: { $0.id == id })?.colorIndex
    }
    var loadedCount: Int { status?.modelsLoaded ?? modelList?.loadedCount ?? 0 }
    var discoveredCount: Int { status?.modelsDiscovered ?? models.count }
    var activeRequests: Int { status?.activeRequests ?? 0 }
    var waitingRequests: Int { status?.waitingRequests ?? 0 }
    var memoryUsed: Int64? { activity?.activeModels?.modelMemoryUsed ?? status?.modelMemoryUsed }
    var memoryMax: Int64? { activity?.activeModels?.modelMemoryMax ?? status?.modelMemoryMax }
    var pressure: MemoryPressure? { activity?.activeModels?.memoryPressure }
    var todayTotals: UsageTotals? { usageToday?.totals }
    var weekTotals: UsageTotals? { usageWeek?.totals }
    var defaultModel: String? { status?.defaultModel }

    var memoryFraction: Double {
        guard let used = memoryUsed, let max = memoryMax, max > 0 else { return 0 }
        return min(1, Double(used) / Double(max))
    }

    var currentHourTokens: Int {
        let hour = Calendar.current.component(.hour, from: Date())
        guard hour < heatmap.count else { return 0 }
        return heatmap[hour]
    }

    var longestIdleSeconds: Double? {
        let values = liveModels.compactMap { $0.idleSeconds }
        return values.max()
    }

    private func gpuMenuBarText(fallback: String) -> String {
        guard prefs.systemMetricsEnabled, let snapshot = system else { return fallback }
        var parts: [String] = []
        if let gpu = snapshot.gpuDevice { parts.append(String(format: "GPU %.0f%%", gpu)) }
        if let peak = snapshot.peakTemperature { parts.append(String(format: "%.0f°", peak)) }
        return parts.isEmpty ? fallback : parts.joined(separator: " · ")
    }

    func start() {
        guard loop == nil else { return }
        prefs.$activeServerID
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.resetTracking() }
            }
            .store(in: &cancellables)
        prefs.$menuBarMode
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.updateMenuBarTitle() }
            }
            .store(in: &cancellables)

        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                let interval = max(1.0, self?.prefs.pollSeconds ?? 3)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
        systemLoop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollSystem()
                let interval = max(2.0, self?.prefs.pollSeconds ?? 3)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        systemLoop?.cancel()
        systemLoop = nil
    }

    func refresh() async {
        await poll(force: true)
    }

    private func resetTracking() {
        counter = nil
        countersReset = true
        decayedTps = 0
        prefillAverage = 0
        lastSlowPoll = nil
        tpsSeries = []
        taskSeries = []
        taskSamples = []
        taskOrder = []
        taskColors = [:]
        status = nil
        activity = nil
        usageToday = nil
        usageWeek = nil
        modelList = nil
        heatmap = Array(repeating: 0, count: 24)
        liveTps = 0
        system = nil
        Task { await poll(force: true) }
    }

    private func makeClient(timeout: TimeInterval = 6) -> OmlxClient? {
        let server = prefs.activeServer
        serverName = server.name
        guard let url = server.url else {
            setOffline("服务器地址无效：\(server.urlString)")
            return nil
        }
        return OmlxClient(baseURL: url, apiKey: prefs.apiKey, timeout: timeout)
    }

    func poll(force: Bool = false) async {
        let server = prefs.activeServer
        if trackedServer != server.id {
            trackedServer = server.id
            counter = nil
        }
        guard let client = makeClient() else { return }

        do {
            async let statusCall = client.get(ServerStatus.self, "/api/status")
            let (statusValue, latency) = try await statusCall
            let (activityValue, _) = await client.getOptional(ActivityResponse.self, "/admin/api/activity")
            apply(status: statusValue, activity: activityValue, latency: latency)

            let slowInterval = max(45, (prefs.pollSeconds * 15).rounded())
            let needsSlow = force || lastSlowPoll == nil || Date().timeIntervalSince(lastSlowPoll!) >= slowInterval
            if needsSlow {
                lastSlowPoll = Date()
                async let todayCall = client.getOptional(UsageResponse.self, "/admin/api/usage", query: ["range": "today"])
                async let weekCall = client.getOptional(UsageResponse.self, "/admin/api/usage", query: ["range": "7d"])
                async let modelsCall = client.getOptional(ModelStatusList.self, "/v1/models/status")
                let (today, week, models) = await (todayCall, weekCall, modelsCall)
                usageToday = today.0
                usageWeek = week.0
                modelList = models.0
                applyHeatmap()
            }
        } catch {
            setOffline(error.localizedDescription)
        }
    }

    private func pollSystem() async {
        guard prefs.systemMetricsEnabled else {
            if system != nil { system = nil }
            return
        }
        guard isOnline, !systemCollecting else { return }
        systemCollecting = true
        defer { systemCollecting = false }
        let snapshot = await SystemCollector.shared.sample(
            target: prefs.sshTarget,
            fast: system?.macmonReady == true
        )
        system = snapshot
    }

    private func apply(status newValue: ServerStatus, activity newActivity: ActivityResponse?, latency: TimeInterval) {
        let now = Date()
        status = newValue
        activity = newActivity
        isOnline = true
        latencyMillis = latency * 1_000
        lastUpdated = now
        lastError = nil

        let inflightNow = liveModels.flatMap { $0.generating ?? [] }
        inflight = inflightNow
        prefilling = liveModels.flatMap { $0.prefilling ?? [] }
        let prefillingCount = liveModels.reduce(0) { $0 + ($1.prefilling?.count ?? 0) }
        let busy = (newValue.activeRequests ?? 0) > 0 || !inflightNow.isEmpty || prefillingCount > 0
        isBusy = busy

        let completion = newValue.totalCompletionTokens ?? 0
        let prompt = newValue.totalPromptTokens ?? 0
        let freshPrompt = prompt - (newValue.totalCachedTokens ?? 0)
        var measuredDecode = 0.0
        var measuredPrefill = 0.0
        if let previous = counter, !countersReset {
            let dt = now.timeIntervalSince(previous.date)
            if dt > 0.4 {
                measuredDecode = Double(max(0, completion - previous.completion)) / dt
                measuredPrefill = Double(max(0, freshPrompt - previous.freshPrompt)) / dt
            }
        }
        countersReset = false
        counter = Counter(date: now, completion: completion, freshPrompt: freshPrompt)

        let reported = inflightNow.reduce(0.0) { $0 + ($1.tokensPerSecond ?? 0) }
        // /api/status 的 token 计数是攒着一次性跳的：飞的时候整段不动，请求收尾或
        // 前后交替那一轮一口气跳出一千多 token，按 1s 一除就是上千 t/s 的假速度，
        // 纵轴被它顶高、真速度反倒贴底。每请求统计值在的时候一律以它为准，
        // 增量估算只在没有可信速度时兜底，并且不许超过最近高原的两倍
        let ceiling = decayedTps > 1 ? decayedTps * 2 : .infinity
        let fallback = busy && reported <= 0.5 ? min(measuredDecode, ceiling) : 0
        let instant = max(reported, fallback)
        let silent = lastBusyAt.map { now.timeIntervalSince($0) } ?? .infinity
        if instant > 0.5 {
            decayedTps = instant
            lastBusyAt = now
        } else if busy, silent <= Self.sampleHoldSeconds {
            // 这一轮没采到速度不等于停了：任务还在吐字就沿用上一次的速度，
            // 曲线停在高原上，不会每漏采一轮就当场腰斩再冒个尖峰
            decayedTps = max(decayedTps, instant)
        } else if silent < 15 {
            // 真跑完了（或空窗拖太久）才降档衰减，留一条收尾的尾巴
            decayedTps *= 0.5
            if decayedTps < 0.4 { decayedTps = 0 }
        } else {
            decayedTps = 0
        }
        liveTps = decayedTps

        if measuredPrefill > 2 {
            prefillAverage = measuredPrefill
        } else if !busy {
            prefillAverage *= 0.4
            if prefillAverage < 2 { prefillAverage = 0 }
        }
        prefillTps = prefillAverage

        tpsSeries.append(liveTps)
        if tpsSeries.count > 90 { tpsSeries.removeFirst(tpsSeries.count - 90) }
        recordTaskSamples(inflightNow)

        updateMenuBarTitle()
    }

    /// 记下这一次轮询里每个请求的吐字速度，并重排多任务曲线
    private func recordTaskSamples(_ requests: [GeneratingRequest]) {
        var sample: [String: Double] = [:]
        for (offset, request) in requests.enumerated() {
            let key = request.requestId ?? "anonymous-\(offset)"
            sample[key, default: 0] += request.tokensPerSecond ?? 0
        }
        appendTaskSample(sample)
    }

    private func appendTaskSample(_ sample: [String: Double]) {
        taskSamples.append(sample)
        if taskSamples.count > 90 { taskSamples.removeFirst(taskSamples.count - 90) }
        for key in sample.keys where !taskOrder.contains(key) { taskOrder.append(key) }
        let alive = taskSamples.reduce(into: Set<String>()) { $0.formUnion($1.keys) }
        taskOrder.removeAll { !alive.contains($0) }
        if taskOrder.count > 8 { taskOrder = Array(taskOrder.suffix(8)) }
        reassignTaskColors()
        taskSeries = taskOrder.compactMap { id in
            let values = taskSamples.map { $0[id] ?? 0 }
            guard values.contains(where: { $0 > 0.05 }) else { return nil }
            let latest = values.last ?? 0
            return TaskSeries(
                id: id,
                colorIndex: taskColors[id] ?? 0,
                values: values,
                latest: latest,
                isLive: latest > 0.05
            )
        }
    }

    /// 给新出现的任务发一个没被占用的配色；老任务滑出窗口后回收自己的颜色，
    /// 不连带把后面任务的曲线颜色往前挪位
    private func reassignTaskColors() {
        for id in Array(taskColors.keys) where !taskOrder.contains(id) {
            taskColors.removeValue(forKey: id)
        }
        for id in taskOrder where taskColors[id] == nil {
            let taken = Set(taskColors.values)
            if let free = (0..<Palette.taskPalette.count).first(where: { !taken.contains($0) }) {
                taskColors[id] = free
            } else if let idle = taskOrder.first(where: { taskColors[$0] != nil && (taskSamples.last?[$0] ?? 0) <= 0.05 }),
                      let recycled = taskColors.removeValue(forKey: idle) {
                taskColors[id] = recycled
            } else {
                taskColors[id] = 0
            }
        }
    }
    private func applyHeatmap() {
        guard let day = usageToday?.heatmap?.first, var values = day.tokens else { return }
        if values.count < 24 { values += Array(repeating: 0, count: 24 - values.count) }
        if values.count > 24 { values = Array(values.prefix(24)) }
        heatmap = values
    }

    private func setOffline(_ message: String) {
        isOnline = false
        lastError = message
        isBusy = false
        liveTps = 0
        prefillTps = 0
        decayedTps = 0
        inflight = []
        prefilling = []
        latencyMillis = nil
        lastUpdated = Date()
        tpsSeries.append(0)
        if tpsSeries.count > 90 { tpsSeries.removeFirst(tpsSeries.count - 90) }
        appendTaskSample([:])
        updateMenuBarTitle()
    }

    private func updateMenuBarTitle() {
        let loading = (status?.modelsLoading ?? 0) > 0 || liveModels.contains { $0.isLoading == true }
        if !isOnline {
            kind = .offline
        } else if loading {
            kind = .loading
        } else if isBusy || liveTps > 0.5 {
            kind = .busy
        } else {
            kind = .idle
        }

        let words: String
        switch kind {
        case .offline: words = "离线"
        case .loading: words = "载入中"
        case .busy: words = "\(Fmt.tps(liveTps)) t/s"
        case .idle: words = loadedCount > 0 ? "待命" : "无模型"
        }

        switch prefs.menuBarMode {
        case .full: menuBarTitle = words
        case .speed: menuBarTitle = kind == .busy ? words : (kind == .offline ? "离线" : "")
        case .gpu: menuBarTitle = gpuMenuBarText(fallback: words)
        case .iconOnly: menuBarTitle = ""
        }
    }

    func toggleModel(_ model: ModelEntry) async {
        guard let client = makeClient(timeout: 180) else { return }
        let shouldLoad = !(model.loaded ?? false)
        pendingModelID = model.id
        notice = shouldLoad ? "正在加载 \(model.id)…" : "正在卸载 \(model.id)…"
        let path = "/v1/models/\(model.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model.id)/\(shouldLoad ? "load" : "unload")"
        do {
            _ = try await client.raw(path, method: "POST")
            notice = shouldLoad ? "已发起加载：\(model.id)" : "已卸载：\(model.id)"
            modelList = nil
            await poll(force: true)
        } catch {
            notice = "操作失败：\(error.localizedDescription)"
        }
        pendingModelID = nil
        flashNotice()
    }

    func runSpeedProbe() async {
        guard let client = makeClient(timeout: 90) else { return }
        guard let model = defaultModel ?? models.first?.id else {
            notice = "没有已加载的模型可测速"
            flashNotice()
            return
        }
        probing = true
        notice = "测速请求已发出…"
        let payload: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": "从 1 数到 40，用空格分隔，只输出数字。"]],
            "max_tokens": 160,
            "temperature": 0,
            "stream": false,
        ]
        defer { probing = false }
        do {
            let body = try JSONSerialization.data(withJSONObject: payload)
            let started = Date()
            let (data, _) = try await client.raw("/v1/chat/completions", method: "POST", body: body)
            let elapsed = Date().timeIntervalSince(started)
            let parsed = try? JSONDecoder().decode(CompletionResponse.self, from: data)
            let tokens = parsed?.usage?.completionTokens ?? 0
            if tokens > 0, elapsed > 0 {
                notice = String(format: "测速完成：%d tokens / %.2fs ≈ %.1f t/s（含首字延迟）", tokens, elapsed, Double(tokens) / elapsed)
            } else {
                notice = "测速完成，但响应里没有 token 统计"
            }
            await poll(force: true)
        } catch {
            notice = "测速失败：\(error.localizedDescription)"
        }
        flashNotice()
    }

    private func flashNotice() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    func dashboardURL(path: String = "/admin/dashboard") -> URL? {
        prefs.activeServer.url?.appendingPathComponent(path)
    }
}
