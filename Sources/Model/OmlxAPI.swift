import Foundation

struct ServerStatus: Codable {
    var status: String?
    var version: String?
    var uptimeSeconds: Double?
    var modelsDiscovered: Int?
    var modelsLoaded: Int?
    var modelsLoading: Int?
    var defaultModel: String?
    var loadedModels: [String]?
    var totalRequests: Int?
    var activeRequests: Int?
    var waitingRequests: Int?
    var totalPromptTokens: Int?
    var totalCompletionTokens: Int?
    var totalCachedTokens: Int?
    var cacheEfficiency: Double?
    var avgPrefillTps: Double?
    var avgGenerationTps: Double?
    var modelMemoryUsed: Int64?
    var modelMemoryMax: Int64?

    enum CodingKeys: String, CodingKey {
        case status, version
        case uptimeSeconds = "uptime_seconds"
        case modelsDiscovered = "models_discovered"
        case modelsLoaded = "models_loaded"
        case modelsLoading = "models_loading"
        case defaultModel = "default_model"
        case loadedModels = "loaded_models"
        case totalRequests = "total_requests"
        case activeRequests = "active_requests"
        case waitingRequests = "waiting_requests"
        case totalPromptTokens = "total_prompt_tokens"
        case totalCompletionTokens = "total_completion_tokens"
        case totalCachedTokens = "total_cached_tokens"
        case cacheEfficiency = "cache_efficiency"
        case avgPrefillTps = "avg_prefill_tps"
        case avgGenerationTps = "avg_generation_tps"
        case modelMemoryUsed = "model_memory_used"
        case modelMemoryMax = "model_memory_max"
    }
}

struct ActivityResponse: Codable {
    var activeModels: ActivityModels?

    enum CodingKeys: String, CodingKey {
        case activeModels = "active_models"
    }
}

struct ActivityModels: Codable {
    var models: [ModelActivity]?
    var modelMemoryUsed: Int64?
    var modelMemoryMax: Int64?
    var memoryPressure: MemoryPressure?
    var totalActiveRequests: Int?
    var totalWaitingRequests: Int?

    enum CodingKeys: String, CodingKey {
        case models
        case modelMemoryUsed = "model_memory_used"
        case modelMemoryMax = "model_memory_max"
        case memoryPressure = "memory_pressure"
        case totalActiveRequests = "total_active_requests"
        case totalWaitingRequests = "total_waiting_requests"
    }
}

struct MemoryPressure: Codable {
    var enabled: Bool?
    var currentBytes: Int64?
    var softBytes: Int64?
    var hardBytes: Int64?
    var currentFormatted: String?
    var softFormatted: String?
    var hardFormatted: String?
    var pressureLevel: String?

    enum CodingKeys: String, CodingKey {
        case enabled
        case currentBytes = "current_bytes"
        case softBytes = "soft_bytes"
        case hardBytes = "hard_bytes"
        case currentFormatted = "current_formatted"
        case softFormatted = "soft_formatted"
        case hardFormatted = "hard_formatted"
        case pressureLevel = "pressure_level"
    }
}

struct ModelActivity: Codable, Identifiable {
    var id: String
    var estimatedSize: Int64?
    var actualSize: Int64?
    var pinned: Bool?
    var isLoading: Bool?
    var loadingElapsedSeconds: Double?
    var loadingRemainingSecondsEstimate: Double?
    var activeRequests: Int?
    var waitingRequests: Int?
    var generating: [GeneratingRequest]?
    var prefilling: [InflightRequest]?
    var waiting: [InflightRequest]?
    var idleSeconds: Double?
    var ttlRemainingSeconds: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case estimatedSize = "estimated_size"
        case actualSize = "actual_size"
        case pinned
        case isLoading = "is_loading"
        case loadingElapsedSeconds = "loading_elapsed_seconds"
        case loadingRemainingSecondsEstimate = "loading_remaining_seconds_estimate"
        case activeRequests = "active_requests"
        case waitingRequests = "waiting_requests"
        case generating
        case prefilling
        case waiting
        case idleSeconds = "idle_seconds"
        case ttlRemainingSeconds = "ttl_remaining_seconds"
    }
}

struct GeneratingRequest: Codable {
    var requestId: String?
    var elapsedSeconds: Double?
    var generatedTokens: Int?
    var tokensPerSecond: Double?
    var lastActivityAgeSeconds: Double?
    var promptTokens: Int?
    var maxTokens: Int?
    var progress: Double?

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case elapsedSeconds = "elapsed_seconds"
        case generatedTokens = "generated_tokens"
        case tokensPerSecond = "tokens_per_second"
        case lastActivityAgeSeconds = "last_activity_age_seconds"
        case promptTokens = "prompt_tokens"
        case maxTokens = "max_tokens"
        case progress
    }
}

struct InflightRequest: Codable {
    var requestId: String?
    var elapsedSeconds: Double?
    var promptTokens: Int?
    var processed: Int?
    var total: Int?
    var speed: Double?
    var eta: Double?
    var phase: String?
    var detail: String?
    var cachedTokens: Int?

    /// 预填充进度：已处理 token / 需要处理的 token。
    var progress: Double? {
        if let processed, let total, total > 0 { return min(1, max(0, Double(processed) / Double(total))) }
        return nil
    }

    /// 预填充速度：优先用服务端上报，其次用「已处理 / 已耗时」，最后回落到本地测得的增量。
    var estimatedSpeed: Double? {
        if let speed, speed > 1 { return speed }
        if let processed, let elapsed = elapsedSeconds, elapsed > 0.25 {
            return Double(processed) / elapsed
        }
        return nil
    }

    private enum LegacyKeys: String, CodingKey {
        case elapsedSeconds = "elapsed_seconds"
    }

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case elapsedSeconds = "elapsed"
        case promptTokens = "prompt_tokens"
        case processed
        case total
        case speed
        case eta
        case phase
        case detail
        case cachedTokens = "cached_tokens"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestId = try container.decodeIfPresent(String.self, forKey: .requestId)
        elapsedSeconds = try container.decodeIfPresent(Double.self, forKey: .elapsedSeconds)
        if elapsedSeconds == nil {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            elapsedSeconds = try legacy.decodeIfPresent(Double.self, forKey: .elapsedSeconds)
        }
        promptTokens = try container.decodeIfPresent(Int.self, forKey: .promptTokens)
        processed = try container.decodeIfPresent(Int.self, forKey: .processed)
        total = try container.decodeIfPresent(Int.self, forKey: .total)
        speed = try container.decodeIfPresent(Double.self, forKey: .speed)
        eta = try container.decodeIfPresent(Double.self, forKey: .eta)
        phase = try container.decodeIfPresent(String.self, forKey: .phase)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        cachedTokens = try container.decodeIfPresent(Int.self, forKey: .cachedTokens)
    }

    init(requestId: String?, elapsedSeconds: Double?, promptTokens: Int?, processed: Int? = nil,
         total: Int? = nil, speed: Double? = nil, eta: Double? = nil, phase: String? = nil,
         detail: String? = nil, cachedTokens: Int? = nil) {
        self.requestId = requestId
        self.elapsedSeconds = elapsedSeconds
        self.promptTokens = promptTokens
        self.processed = processed
        self.total = total
        self.speed = speed
        self.eta = eta
        self.phase = phase
        self.detail = detail
        self.cachedTokens = cachedTokens
    }
}

struct ModelStatusList: Codable {
    var finalCeiling: Int64?
    var currentModelMemory: Int64?
    var modelCount: Int?
    var loadedCount: Int?
    var loadSecondsPerGbEstimate: Double?
    var models: [ModelEntry]?

    enum CodingKeys: String, CodingKey {
        case finalCeiling = "final_ceiling"
        case currentModelMemory = "current_model_memory"
        case modelCount = "model_count"
        case loadedCount = "loaded_count"
        case loadSecondsPerGbEstimate = "load_seconds_per_gb_estimate"
        case models
    }
}

struct ModelEntry: Codable, Identifiable {
    var id: String
    var loaded: Bool?
    var isLoading: Bool?
    var estimatedSize: Int64?
    var actualSize: Int64?
    var pinned: Bool?
    var engineType: String?
    var modelType: String?
    var modelContextLength: Int?
    var maxContextWindow: Int?
    var maxTokens: Int?
    var isFavorite: Bool?
    var isHidden: Bool?
    var lastAccess: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case loaded
        case isLoading = "is_loading"
        case estimatedSize = "estimated_size"
        case actualSize = "actual_size"
        case pinned
        case engineType = "engine_type"
        case modelType = "model_type"
        case modelContextLength = "model_context_length"
        case maxContextWindow = "max_context_window"
        case maxTokens = "max_tokens"
        case isFavorite = "is_favorite"
        case isHidden = "is_hidden"
        case lastAccess = "last_access"
    }
}

struct UsageResponse: Codable {
    var range: String?
    var available: Bool?
    var totals: UsageTotals?
    var models: [UsageModelRow]?
    var heatmap: [HeatmapDay]?
}

struct UsageTotals: Codable {
    var requests: Int?
    var promptTokens: Int?
    var completionTokens: Int?
    var cachedTokens: Int?
    var prefillSeconds: Double?
    var generationSeconds: Double?
    var requestSeconds: Double?
    var timedRequests: Int?
    var totalTokens: Int?
    var cacheEfficiency: Double?
    var generationTps: Double?
    var prefillTps: Double?
    var averageRequestSeconds: Double?

    enum CodingKeys: String, CodingKey {
        case requests
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case cachedTokens = "cached_tokens"
        case prefillSeconds = "prefill_seconds"
        case generationSeconds = "generation_seconds"
        case requestSeconds = "request_seconds"
        case timedRequests = "timed_requests"
        case totalTokens = "total_tokens"
        case cacheEfficiency = "cache_efficiency"
        case generationTps = "generation_tps"
        case prefillTps = "prefill_tps"
        case averageRequestSeconds = "average_request_seconds"
    }
}

struct UsageModelRow: Codable, Identifiable {
    var modelId: String
    var requests: Int?
    var totalTokens: Int?
    var promptTokens: Int?
    var completionTokens: Int?
    var cachedTokens: Int?
    var generationTps: Double?
    var cacheEfficiency: Double?
    var generationSeconds: Double?

    var id: String { modelId }

    enum CodingKeys: String, CodingKey {
        case modelId = "model_id"
        case requests
        case totalTokens = "total_tokens"
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case cachedTokens = "cached_tokens"
        case generationTps = "generation_tps"
        case cacheEfficiency = "cache_efficiency"
        case generationSeconds = "generation_seconds"
    }
}

struct HeatmapDay: Codable {
    var date: String?
    var tokens: [Int]?
}

struct HealthResponse: Codable {
    var status: String?
    var defaultModel: String?
    var enginePool: EnginePool?

    enum CodingKeys: String, CodingKey {
        case status
        case defaultModel = "default_model"
        case enginePool = "engine_pool"
    }
}

struct EnginePool: Codable {
    var modelCount: Int?
    var loadedCount: Int?
    var finalCeiling: Int64?
    var currentModelMemory: Int64?

    enum CodingKeys: String, CodingKey {
        case modelCount = "model_count"
        case loadedCount = "loaded_count"
        case finalCeiling = "final_ceiling"
        case currentModelMemory = "current_model_memory"
    }
}
