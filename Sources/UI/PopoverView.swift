import SwiftUI
import AppKit

struct PopoverView: View {
    @ObservedObject var state: WidgetState
    @ObservedObject var prefs: Preferences

    init(state: WidgetState = WidgetState.shared, prefs: Preferences = Preferences.shared) {
        self.state = state
        self.prefs = prefs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            if let notice = state.notice {
                banner(text: notice, tint: Color.accentColor)
            }
            if let error = state.lastError, !state.isOnline {
                banner(text: error, tint: Palette.kind(.offline))
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 9) {
                    liveCard
                    memoryCard
                    if prefs.systemMetricsEnabled {
                        systemCard
                    }
                    usageCard
                    modelsCard
                }
            }
            .frame(maxHeight: 470)
            footer
        }
        .padding(12)
        .frame(width: 372)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                StatusDot(kind: state.kind, size: 10)
                Text("oMLX")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text(state.kind.label)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Palette.kind(state.kind).opacity(0.18)))
                    .foregroundStyle(Palette.kind(state.kind))
                Spacer()
                if let version = state.status?.version {
                    Text("v\(version)")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            HStack(spacing: 8) {
                Text(state.serverName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(prefs.activeServer.displayHost)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer()
                if state.isOnline {
                    if let latency = state.latencyMillis {
                        Label(String(format: "%.0f ms", latency), systemImage: "wifi")
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    Text("更新于 \(Fmt.clock(state.lastUpdated))")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            if let uptime = state.status?.uptimeSeconds {
                HStack(spacing: 10) {
                    Chip(text: "运行 \(Fmt.duration(uptime))", systemImage: "clock.arrow.circlepath")
                    Chip(text: "\(state.loadedCount)/\(max(state.discoveredCount, state.loadedCount)) 模型已加载", systemImage: "square.stack.3d.up")
                    if let idle = state.longestIdleSeconds, !state.isBusy, idle >= 30 {
                        Chip(text: "空闲 \(Fmt.duration(idle))", systemImage: "moon.zzz")
                    }
                }
            }
        }
    }

    private var liveCard: some View {
        let caption: String
        if state.isBusy {
            caption = "实时生成速度"
        } else if state.liveTps > 0.5 {
            caption = "上一次推理收尾速度"
        } else {
            caption = state.isOnline ? "空闲中，发出请求后即时跳数" : "离线，等待隧道或 oMLX 上线"
        }
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(Fmt.tps(state.liveTps))
                                .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(state.liveTps > 0 ? Palette.kind(.busy) : Color.secondary)
                            Text("tokens/s")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Text(caption)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        MetricInline(label: "请求中", value: "\(state.activeRequests)", tint: state.activeRequests > 0 ? Palette.kind(.busy) : nil)
                        MetricInline(label: "排队", value: "\(state.waitingRequests)", tint: state.waitingRequests > 0 ? Palette.kind(.loading) : nil)
                        MetricInline(label: "预填充", value: prefillMetricValue, tint: Palette.prefill)
                    }
                }

                Group {
                    if state.showsTaskCurves {
                        MultiSparkline(curves: taskCurves)
                    } else {
                        Sparkline(values: state.tpsSeries)
                    }
                }
                .frame(height: 44)

                if !state.prefilling.isEmpty || !state.inflight.isEmpty {
                    Divider()
                    ForEach(Array(state.prefilling.enumerated()), id: \.offset) { _, request in
                        prefillRow(request)
                    }
                    ForEach(Array(state.inflight.enumerated()), id: \.offset) { _, request in
                        inflightRow(request)
                    }
                }
            }
        }
    }

    private func inflightProgress(_ request: GeneratingRequest) -> Double? {
        if let progress = request.progress { return progress }
        guard let maxTokens = request.maxTokens, maxTokens > 0 else { return nil }
        return Double(request.generatedTokens ?? 0) / Double(maxTokens)
    }

    private func inflightRow(_ request: GeneratingRequest) -> some View {
        let tint = taskTint(for: request)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 9))
                    .foregroundStyle(tint)
                Text("\(Fmt.grouped(request.generatedTokens)) tokens")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                Spacer()
                Text("\(Fmt.tps(request.tokensPerSecond)) t/s")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(tint)
                Text(String(format: "%.1fs", request.elapsedSeconds ?? 0))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            if let progress = inflightProgress(request) {
                GaugeBar(fraction: progress, tint: tint, height: 3)
            }
        }
    }

    private var taskCurves: [SpeedCurve] {
        state.taskSeries.map { SpeedCurve(id: $0.id, values: $0.values, tint: Palette.task($0.colorIndex)) }
    }

    /// 面板里的逐请求行与曲线用同一个颜色，方便对号
    private func taskTint(for request: GeneratingRequest) -> Color {
        guard let index = state.taskColorIndex(forRequestId: request.requestId) else { return Palette.kind(.busy) }
        return Palette.task(index)
    }

    private var prefillMetricValue: String {
        let speed = state.prefillSpeed
        guard speed > 0.5 else { return "—" }
        if let fraction = state.prefillFraction {
            return "\(Fmt.tps(speed)) t/s · \(Int(fraction * 100))%"
        }
        return "\(Fmt.tps(speed)) t/s"
    }

    private func prefillRow(_ request: InflightRequest) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.prefill)
                Text("预填充 \(Fmt.grouped(request.processed))/\(Fmt.grouped(request.total))")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Palette.prefill)
                Spacer(minLength: 4)
                if let fraction = request.progress {
                    Text("\(Int(fraction * 100))%")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Palette.prefill)
                }
                Text("\(Fmt.tps(request.estimatedSpeed ?? state.prefillSpeed)) t/s")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.prefill)
                Text(String(format: "%.1fs", request.elapsedSeconds ?? 0))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            GaugeBar(fraction: request.progress ?? 0, tint: Palette.prefill, height: 3)
            if request.cachedTokens ?? 0 > 0 {
                Text("命中缓存 \(Fmt.grouped(request.cachedTokens)) tokens")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var memoryCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    SectionLabel(title: "统一内存", systemImage: "memorychip")
                    Spacer()
                    if state.memoryMax != nil {
                        Text(memoryBand.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(memoryBand.tint)
                    }
                    Text(Fmt.percent(state.memoryMax == nil ? nil : Double(state.memoryUsed ?? 0) / Double(state.memoryMax!)))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Palette.load(state.memoryFraction))
                }
                GaugeBar(fraction: state.memoryFraction, markers: pressureMarkers)
                HStack {
                    Text("\(Fmt.bytes(state.memoryUsed)) / \(Fmt.bytes(state.memoryMax))")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let soft = state.pressure?.softFormatted, let hard = state.pressure?.hardFormatted {
                        Text("软 \(soft) · 硬 \(hard)")
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private var pressureMarkers: [Double] {
        guard let pressure = state.pressure, let max = state.memoryMax, max > 0 else { return [] }
        var markers: [Double] = []
        if let soft = pressure.softBytes { markers.append(Double(soft) / Double(max)) }
        if let hard = pressure.hardBytes { markers.append(Double(hard) / Double(max)) }
        return markers
    }

    /// 与浮窗同一套四档判断，oMLX 报出硬压力时直接把档位顶到吃紧
    private var memoryBand: MemoryBand {
        var band = MemoryBand(fraction: state.memoryFraction)
        if state.pressure?.pressureLevel == "hard" { band = .critical }
        return band
    }

    private var systemCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    SectionLabel(title: "GPU 与温度", systemImage: "gauge.with.dots.needle.bottom.50percent")
                    Spacer()
                    thermalChip
                }
                if let snapshot = state.system {
                    gpuHeadline(snapshot)
                    VStack(spacing: 3) {
                        if snapshot.gpuRenderer != nil || snapshot.gpuTiler != nil {
                            MetricRow(
                                label: "Renderer / Tiler",
                                value: "\(Fmt.percent(snapshot.gpuRenderer)) / \(Fmt.percent(snapshot.gpuTiler))"
                            )
                        }
                        MetricRow(label: "CPU 占用", value: Fmt.percent(snapshot.cpuBusy), detail: loadDetail(snapshot))
                        MetricRow(
                            label: "GPU 显存",
                            value: Fmt.compactBytes(snapshot.gpuMemoryInUse),
                            detail: snapshot.ramUsage.map { "系统已用 \(Fmt.compactBytes($0))" }
                        )
                        MetricRow(
                            label: "温度",
                            value: temperatureText(snapshot),
                            detail: temperatureDetail(snapshot),
                            tint: Palette.temperature(snapshot.peakTemperature)
                        )
                        if snapshot.powerTotal != nil || snapshot.fanRPM != nil {
                            MetricRow(label: "功耗 / 风扇", value: powerText(snapshot), detail: fanDetail(snapshot))
                                .lineLimit(1)
                        }
                    }
                    if let error = snapshot.error {
                        Text(error)
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.kind(.offline))
                    }
                    if !snapshot.macmonReady && snapshot.peakTemperature == nil {
                        Text("想看具体摄氏度：在 Studio 上执行 brew install macmon（免 sudo），小工具会自动读到温度与风扇。")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("SSH \(prefs.sshTarget) · 采集于 \(Fmt.clock(snapshot.date))")
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                } else {
                    Text(prefs.sshTarget.trimmingCharacters(in: .whitespaces).isEmpty
                         ? "没填 SSH 地址，采不到 GPU 与温度"
                         : "正在通过 SSH 采集 \(prefs.sshTarget)…")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var thermalChip: some View {
        let level = state.system?.thermalDisplay ?? .unknown
        let tint = Palette.temperature(state.system?.peakTemperature)
        Label(level.label, systemImage: level.systemImage)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.16)))
            .foregroundStyle(tint)
    }

    private func gpuHeadline(_ snapshot: SystemSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(snapshot.gpuDevice.map { String(format: "%.0f", $0) } ?? "—")
                    .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Palette.duty(snapshot.gpuFraction))
                Text("% GPU 占用")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if let mhz = snapshot.gpuFreqMHz, mhz > 0 {
                    Text("\(Int(mhz)) MHz")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            GaugeBar(fraction: snapshot.gpuFraction, tint: Palette.duty(snapshot.gpuFraction), height: 6)
        }
    }

    private func loadDetail(_ snapshot: SystemSnapshot) -> String? {
        guard let one = snapshot.load1 else { return nil }
        let cores = snapshot.coreCount.map { " / \($0) 核" } ?? ""
        return String(format: "负载 %.2f · %.2f · %.2f%@", one, snapshot.load5 ?? 0, snapshot.load15 ?? 0, cores)
    }

    private func temperatureText(_ snapshot: SystemSnapshot) -> String {
        let cpu = snapshot.temperatureCPU.map { String(format: "%.0f°", $0) } ?? "—"
        let gpu = snapshot.temperatureGPU.map { String(format: "%.0f°", $0) } ?? "—"
        return "\(cpu) / \(gpu)"
    }

    private func temperatureDetail(_ snapshot: SystemSnapshot) -> String? {
        guard snapshot.temperatureCPU != nil || snapshot.temperatureGPU != nil else { return nil }
        return "CPU / GPU"
    }

    private func powerText(_ snapshot: SystemSnapshot) -> String {
        guard let total = snapshot.powerTotal else { return "—" }
        return String(format: "%.1f W", total)
    }

    private func fanDetail(_ snapshot: SystemSnapshot) -> String? {
        var parts: [String] = []
        if let rpm = snapshot.fanRPM { parts.append(String(format: "风扇 %.0f rpm", rpm)) }
        if let gpu = snapshot.powerGPU, gpu >= 0.5 { parts.append(String(format: "GPU %.0f W", gpu)) }
        if let cpu = snapshot.powerCPU, cpu >= 1 { parts.append(String(format: "CPU %.0f W", cpu)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var usageCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    SectionLabel(title: "今日用量", systemImage: "chart.bar.xaxis")
                    Spacer()
                    if let week = state.weekTotals {
                        Text("7 天 \(Fmt.compactTokens(week.totalTokens)) tokens")
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
                if let today = state.todayTotals {
                    HStack(alignment: .top, spacing: 14) {
                        StatBlock(title: "请求", value: Fmt.grouped(today.requests))
                        StatBlock(title: "tokens", value: Fmt.compactTokens(today.totalTokens))
                        StatBlock(title: "缓存命中", value: Fmt.percent(today.cacheEfficiency))
                        StatBlock(title: "平均耗时", value: Fmt.shortDuration(today.averageRequestSeconds))
                    }
                    HStack(alignment: .top, spacing: 14) {
                        StatBlock(title: "生成均速", value: today.generationTps.map { "\(Fmt.tps($0)) t/s" } ?? "—")
                        StatBlock(title: "预填充均速", value: today.prefillTps.map { "\(Fmt.tps($0)) t/s" } ?? "—")
                        StatBlock(title: "补全 tokens", value: Fmt.compactTokens(today.completionTokens))
                    }
                    if prefs.showHeatmap {
                        VStack(alignment: .leading, spacing: 3) {
                            HeatBars(values: state.heatmap, currentHour: Calendar.current.component(.hour, from: Date()))
                                .frame(height: 26)
                            HStack {
                                Text("0")
                                Spacer()
                                Text("12")
                                Spacer()
                                Text("当前小时 \(Fmt.compactTokens(state.currentHourTokens))")
                            }
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(.quaternary)
                        }
                        .padding(.top, 2)
                    }
                } else {
                    Text(state.isOnline ? "用量数据加载中…" : "离线")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var modelsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    SectionLabel(title: "模型", systemImage: "cube.stack")
                    Spacer()
                    Text("\(state.models.count) 个")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                if state.models.isEmpty {
                    Text(state.isOnline ? "没有发现本地模型" : "离线，暂无模型清单")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                ForEach(state.models) { model in
                    modelRow(model)
                }
            }
        }
    }

    private func modelRow(_ model: ModelEntry) -> some View {
        let isLoaded = model.loaded ?? false
        let pending = state.pendingModelID == model.id
        return HStack(spacing: 8) {
            Circle()
                .fill(isLoaded ? Palette.kind(.busy) : Color.secondary.opacity(0.4))
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.id)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(Fmt.bytes(model.actualSize ?? model.estimatedSize))
                    Text("ctx \(Fmt.compactTokens(model.maxContextWindow ?? model.modelContextLength))")
                    if model.pinned == true { Text("常驻") }
                    if let engine = model.engineType { Text(engine) }
                }
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            if pending {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
            } else {
                GhostButton(
                    title: isLoaded ? "卸载" : "加载",
                    systemImage: isLoaded ? "square.stack.3d.up.slash" : "square.stack.3d.down.forward",
                    isDisabled: model.isLoading == true
                ) {
                    Task { await state.toggleModel(model) }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            GhostButton(title: state.probing ? "测速中" : "测速", systemImage: "stopwatch", isDisabled: state.probing || !state.isOnline) {
                Task { await state.runSpeedProbe() }
            }
            GhostButton(title: "刷新", systemImage: "arrow.clockwise") {
                Task { await state.refresh() }
            }
            GhostButton(title: "控制台", systemImage: "safari") {
                if let url = state.dashboardURL() {
                    NSWorkspace.shared.open(url)
                }
            }
            Spacer(minLength: 4)
            GhostButton(
                title: prefs.showFloatingCard ? "收起桌面浮窗" : "显示桌面浮窗",
                systemImage: prefs.showFloatingCard ? "rectangle.center.inset.filled" : "rectangle.dashed",
                showsTitle: false
            ) {
                prefs.showFloatingCard.toggle()
            }
            GhostButton(
                title: "外观：\(prefs.appearanceMode.label)（点一下切换）",
                systemImage: prefs.appearanceMode.symbol,
                showsTitle: false
            ) {
                prefs.appearanceMode = prefs.appearanceMode.next
            }
            GhostButton(title: "设置", systemImage: "gearshape", showsTitle: false) {
                AppController.shared?.showSettings()
            }
            GhostButton(title: "退出", systemImage: "power", showsTitle: false) {
                NSApp.terminate(nil)
            }
        }
    }

    private func banner(text: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.opacity(0.12)))
    }
}

struct Chip: View {
    var text: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage).font(.system(size: 8))
            Text(text).font(.system(size: 10).monospacedDigit())
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.primary.opacity(0.05)))
    }
}

struct MetricInline: View {
    var label: String
    var value: String
    var tint: Color?

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(tint ?? Color.primary)
        }
    }
}

struct StatBlock: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
