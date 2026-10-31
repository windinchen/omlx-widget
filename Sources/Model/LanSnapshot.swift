import Foundation

/// 局域网网页上的一帧数据：把浮窗与详情面板里的东西压成一份 JSON，
/// 手机 / 别的电脑只轮询这一个接口就够，不需要知道 oMLX 的接口长什么样
struct LanSnapshot: Codable {
    struct Server: Codable {
        var name: String
        var url: String
        var kind: String
        var kindLabel: String
        var online: Bool
        var latencyMillis: Double?
        var updatedAt: String?
        var error: String?
        var needsAPIKey: Bool
    }

    /// 一条任务的曲线：与浮窗的多色曲线同一配色序号，网页照着画就行
    struct Task: Codable {
        var label: String
        var colorIndex: Int
        var latest: Double
        var live: Bool
        var series: [Double]
    }

    struct Speed: Codable {
        var tps: Double
        var series: [Double]
        var tasks: [Task]
        var activeRequests: Int
        var waitingRequests: Int
        var busy: Bool
    }

    struct Prefill: Codable {
        var percent: Int
        var speed: Double
        var processed: Int?
        var total: Int?
        var etaSeconds: Double?
    }

    struct Memory: Codable {
        var percent: Double?
        var used: Int64?
        var max: Int64?
        var usedText: String
        var maxText: String
        var label: String
        var softBytes: Int64?
        var hardBytes: Int64?
    }

    struct System: Codable {
        var gpuDevice: Double?
        var gpuRenderer: Double?
        var gpuTiler: Double?
        var gpuMemory: Int64?
        var cpuBusy: Double?
        var load1: Double?
        var temperatureCPU: Double?
        var temperatureGPU: Double?
        var powerTotal: Double?
        var fanRPM: Double?
        var fanMaxRPM: Double?
        var thermalLabel: String
        var sourceLabel: String
        var collectedAt: String?
        var macmonReady: Bool
        var error: String?
    }

    struct Usage: Codable {
        var requests: Int?
        var totalTokens: Int?
        var totalTokensText: String
        var cacheEfficiency: Double?
        var averageSeconds: Double?
        var generationTps: Double?
        var prefillTps: Double?
    }

    struct Model: Codable, Identifiable {
        var id: String
        var loaded: Bool
        var loading: Bool
        var sizeText: String
        var context: Int?
        var pinned: Bool
        var engine: String?
    }

    var version: String
    var pollSeconds: Double
    var server: Server
    var speed: Speed
    var prefill: Prefill?
    var memory: Memory
    var system: System?
    var today: Usage?
    var week: Usage?
    var heatmap: [Int]
    var models: [Model]
    var consoleURL: String?
    /// 面板里那条一闪而过的提示（测速结果、加载结果），网页也照样显示
    var notice: String?
}

@MainActor
extension WidgetState {
    /// 给局域网页面的一帧数据。浮窗和面板读的是同一批 @Published 字段，
    /// 这里只是换个壳，不额外发请求，所以网页轮询不会给 oMLX 增加负担
    func lanSnapshot() -> LanSnapshot {
        let fraction = memoryFraction
        return LanSnapshot(
            version: AppVersion.current.description,
            pollSeconds: max(1, Preferences.shared.pollSeconds),
            server: LanSnapshot.Server(
                name: serverName,
                url: Preferences.shared.activeServer.urlString,
                kind: kind.webName,
                kindLabel: kind.label,
                online: isOnline,
                latencyMillis: latencyMillis,
                updatedAt: Fmt.clock(lastUpdated),
                error: lastError,
                needsAPIKey: needsAPIKey
            ),
            speed: LanSnapshot.Speed(
                tps: liveTps,
                series: Array(tpsSeries.suffix(60)),
                tasks: lanTasks(),
                activeRequests: activeRequests,
                waitingRequests: waitingRequests,
                busy: isBusy
            ),
            prefill: lanPrefill(),
            memory: LanSnapshot.Memory(
                percent: fraction > 0 ? fraction * 100 : nil,
                used: memoryUsed,
                max: memoryMax,
                usedText: Fmt.compactBytes(memoryUsed),
                maxText: Fmt.compactBytes(memoryMax),
                label: fraction > 0 ? MemoryBand(fraction: fraction).label : "—",
                softBytes: pressure?.softBytes,
                hardBytes: pressure?.hardBytes
            ),
            system: lanSystem(),
            today: lanUsage(todayTotals),
            week: lanUsage(weekTotals),
            heatmap: heatmap,
            models: models.prefix(80).map {
                LanSnapshot.Model(
                    id: $0.id,
                    loaded: $0.loaded ?? false,
                    loading: $0.isLoading ?? false,
                    sizeText: Fmt.compactBytes($0.estimatedSize ?? $0.actualSize),
                    context: $0.modelContextLength ?? $0.maxContextWindow,
                    pinned: $0.pinned ?? false,
                    engine: $0.engineType
                )
            },
            consoleURL: dashboardURL()?.absoluteString,
            notice: notice
        )
    }

    /// 曲线只给还在吐字的任务，标签取它挂在哪个模型上，配色序号沿用浮窗那套
    private func lanTasks() -> [LanSnapshot.Task] {
        liveTaskSeries.compactMap { series in
            guard series.latest > 0.05 else { return nil }
            return LanSnapshot.Task(
                label: Self.modelOwning(requestID: series.id, in: liveModels) ?? String(series.id.prefix(8)),
                colorIndex: series.colorIndex,
                latest: series.latest,
                live: series.isLive,
                series: Array(series.values.suffix(60))
            )
        }
    }

    private static func modelOwning(requestID: String?, in models: [ModelActivity]) -> String? {
        guard let requestID else { return nil }
        for model in models {
            let ids = (model.generating ?? []).compactMap { $0.requestId }
                + (model.prefilling ?? []).compactMap { $0.requestId }
            if ids.contains(requestID) { return model.id }
        }
        return nil
    }

    private func lanPrefill() -> LanSnapshot.Prefill? {
        guard let top = prefilling.max(by: { ($0.progress ?? 0) < ($1.progress ?? 0) }) else { return nil }
        return LanSnapshot.Prefill(
            percent: Int(((top.progress ?? 0) * 100).rounded()),
            speed: prefillSpeed,
            processed: top.processed,
            total: top.total,
            etaSeconds: top.eta
        )
    }

    private func lanSystem() -> LanSnapshot.System? {
        guard let snapshot = system, snapshot.hasAnyValue || snapshot.error != nil else { return nil }
        return LanSnapshot.System(
            gpuDevice: snapshot.gpuDevice,
            gpuRenderer: snapshot.gpuRenderer,
            gpuTiler: snapshot.gpuTiler,
            gpuMemory: snapshot.gpuMemoryInUse,
            cpuBusy: snapshot.cpuBusy,
            load1: snapshot.load1,
            temperatureCPU: snapshot.temperatureCPU,
            temperatureGPU: snapshot.temperatureGPU,
            powerTotal: snapshot.powerTotal,
            fanRPM: snapshot.fanRPM,
            fanMaxRPM: snapshot.fanMaxRPM,
            thermalLabel: snapshot.thermalDisplay.label,
            sourceLabel: snapshot.source.isLocal ? "本机采集" : "SSH \(Preferences.shared.sshTarget)",
            collectedAt: Fmt.clock(snapshot.date),
            macmonReady: snapshot.macmonReady,
            error: snapshot.error
        )
    }

    private func lanUsage(_ totals: UsageTotals?) -> LanSnapshot.Usage? {
        guard let totals else { return nil }
        return LanSnapshot.Usage(
            requests: totals.requests,
            totalTokens: totals.totalTokens,
            totalTokensText: Fmt.compactTokens(totals.totalTokens),
            cacheEfficiency: totals.cacheEfficiency,
            averageSeconds: totals.averageRequestSeconds,
            generationTps: totals.generationTps,
            prefillTps: totals.prefillTps
        )
    }
}

extension WidgetKind {
    /// 网页按这个短名取状态色，与 Palette.kind 的四档一一对应
    var webName: String {
        switch self {
        case .offline: return "offline"
        case .idle: return "idle"
        case .busy: return "busy"
        case .loading: return "loading"
        }
    }
}
