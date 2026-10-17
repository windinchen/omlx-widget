import AppKit
import SwiftUI

/// 浮窗基准尺寸：字号调大时整张卡片等比放大，避免文字被挤断
enum FloatingCardLayout {
    static let baseWidth: CGFloat = 246
    static let baseHeight: CGFloat = 157
    /// 竖向仪表样式多了左右两列竖表，卡片相应加高
    static let gaugeHeight: CGFloat = 185

    static func factor(_ fontScale: Double) -> CGFloat {
        CGFloat(min(1.4, max(0.8, fontScale)))
    }

    static func size(fontScale: Double, style: CardStyle = .curves) -> NSSize {
        let factor = factor(fontScale)
        let base = style == .gauge ? gaugeHeight : baseHeight
        return NSSize(width: (baseWidth * factor).rounded(), height: (base * factor).rounded())
    }

    /// 竖表那一列的高度，不含卡片内边距
    static func meterHeight(fontScale: Double) -> CGFloat {
        (58 * factor(fontScale)).rounded()
    }

    /// 右上角关闭按钮的命中区，窗口坐标系（原点在左下）；拖动与点击的判定以它为准
    static func closeRect(fontScale: Double, in size: NSSize) -> NSRect {
        let f = factor(fontScale)
        let side = (26 * f).rounded()
        let margin = (4 * f).rounded()
        return NSRect(x: size.width - side - margin, y: size.height - side - margin + 4, width: side, height: side)
    }
}

/// 卡片格子里的状态角标：文案 + 取色 + 要不要把整格点亮成告警色
struct TileStatus {
    var text: String
    var tint: Color
    var alert: Bool
}

struct FloatingCardView: View {
    @ObservedObject var state: WidgetState
    @ObservedObject var prefs: Preferences

    init(state: WidgetState = WidgetState.shared, prefs: Preferences = Preferences.shared) {
        self.state = state
        self.prefs = prefs
    }

    /// 只有背景跟随"不透明度"，文字与图表始终满强度绘制，不再被半透明拉低

    /// 字色亮度档位：0 是原样，1 最亮
    private var level: Double { prefs.cardIntensity }

    private var fontScale: CGFloat { FloatingCardLayout.factor(prefs.cardFontScale) }

    private var cardWidth: CGFloat { FloatingCardLayout.size(fontScale: prefs.cardFontScale).width }

    /// 三级文字色用 primary 的不透明度表达对比度，深浅色模式都能自适应
    private var inkStrong: Color { Color.primary.opacity(min(1, 0.92 + 0.08 * level)) }
    private var inkMid: Color { Color.primary.opacity(min(1, 0.62 + 0.38 * level)) }
    private var inkFaint: Color { Color.primary.opacity(min(1, 0.42 + 0.58 * level)) }

    /// 文字不透明度封顶是纯白，所以顶端再叠同色辉光 + 淡对比衬底，把峰值亮度和文字对比度一起抬上去
    private var inkGlow: Color { Color.primary.opacity(0.55 * level * level) }

    /// 用 .textBackgroundColor 做衬底：深色模式压暗、浅色模式提亮，两种外观都是加对比
    private var contrastScrim: Color {
        Color(nsColor: .textBackgroundColor).opacity(0.20 * level)
    }

    private var prefillTint: Color { Vivid.apply(Palette.prefill, level: level) }

    private func cardFont(_ size: Double, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: (CGFloat(size) * fontScale).rounded(), weight: weight, design: design)
    }

    var body: some View {
        cardChrome {
            if prefs.cardStyle == .gauge {
                dashboardRows
            } else {
                classicRows
            }
        }
    }

    /// 两种样式共用的卡片外壳：底色、辉光、描边和预填充漫过只画一份
    @ViewBuilder
    private func cardChrome<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding((11 * fontScale).rounded())
            .frame(width: cardWidth)
            .shadow(color: inkGlow, radius: 1.6 * fontScale * CGFloat(level))
            .shadow(color: inkGlow, radius: 5.0 * fontScale * CGFloat(level))
            .background {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 14 * fontScale, style: .continuous)
                        .fill(.regularMaterial)
                        .opacity(prefs.cardOpacity)
                    RoundedRectangle(cornerRadius: 14 * fontScale, style: .continuous)
                        .fill(contrastScrim)
                    prefillFill
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14 * fontScale, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14 * fontScale, style: .continuous)
                    .strokeBorder(
                        state.isPrefilling
                            ? prefillTint.opacity(0.75)
                            : Color.primary.opacity(0.12 + 0.16 * level),
                        lineWidth: state.isPrefilling ? 1.2 : 0.5
                    )
            )
    }

    /// 默认样式：速度曲线在上，内存与 GPU 各一条横向细条
    private var classicRows: some View {
        VStack(alignment: .leading, spacing: (7 * fontScale).rounded()) {
            headerRow
            speedRow

            Group {
                if showsTaskBars {
                    TaskSpeedBars(tasks: liveTasks, scale: fontScale, intensity: level)
                } else if state.showsTaskCurves {
                    MultiSparkline(curves: taskCurves, intensity: level)
                } else {
                    Sparkline(values: state.tpsSeries, intensity: level)
                }
            }
            .frame(height: showsTaskBars
                ? TaskSpeedBars.height(rows: liveTasks.count, scale: fontScale)
                : (22 * fontScale).rounded())

            // 预填充时这一行换成蓝色进度文案（整张卡片本身就是进度条），高度固定，卡片不会跳动或裁切
            Group {
                if state.isPrefilling {
                    Text(prefillBadge())
                        .font(cardFont(9, weight: .semibold).monospacedDigit())
                        .foregroundStyle(prefillTint)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if showsTaskLegend {
                    taskLegend()
                } else {
                    GaugeBar(fraction: state.memoryFraction, markers: [0.85, 0.95], height: 4 * fontScale, intensity: level)
                }
            }
            .frame(height: (12 * fontScale).rounded())

            HStack {
                Text("\(Fmt.compactBytes(state.memoryUsed)) / \(Fmt.compactBytes(state.memoryMax))")
                Spacer()
                Text("\(Fmt.compactTokens(state.todayTotals?.totalTokens)) tok")
            }
            .font(cardFont(9).monospacedDigit())
            .foregroundStyle(inkFaint)
            .lineLimit(1)

            if let snapshot = state.system, snapshot.gpuDevice != nil || snapshot.peakTemperature != nil {
                HStack(spacing: 5) {
                    GaugeBar(
                        fraction: snapshot.gpuFraction,
                        tint: Palette.duty(snapshot.gpuFraction),
                        height: 3 * fontScale,
                        intensity: level
                    )
                    Text(gpuBadge(snapshot))
                        .foregroundStyle(Vivid.apply(Palette.temperature(snapshot.peakTemperature), level: level))
                        .fixedSize(horizontal: true, vertical: false)
                }
                .font(cardFont(9).monospacedDigit())
                .foregroundStyle(inkFaint)
                .lineLimit(1)
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            StatusDot(kind: state.kind, size: 8 * fontScale, intensity: level)
            Text(prefs.activeServer.name)
                .font(cardFont(11, weight: .semibold))
                .foregroundStyle(inkStrong)
                .lineLimit(1)
            Spacer(minLength: 4)
            // 关闭点击由 FloatingPanel 统一判定（命中区见 FloatingCardLayout.closeRect），
            // 这里只画图标：SwiftUI 按钮的事件跟踪会抢走 mouseDragged，让卡片拖不动
            Image(systemName: "xmark")
                .font(cardFont(8, weight: .bold))
                .foregroundStyle(inkFaint)
        }
    }

    private var speedRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(Fmt.tps(state.liveTps))
                .font(cardFont(26, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(state.liveTps > 0 ? Vivid.apply(Palette.kind(.busy), level: level) : inkStrong)
            Text("t/s")
                .font(cardFont(10, weight: .medium))
                .foregroundStyle(inkMid)
            Spacer()
            Text(state.kind.label)
                .font(cardFont(10, weight: .semibold))
                .foregroundStyle(Vivid.apply(Palette.kind(state.kind), level: level))
        }
    }

    /// 竖向仪表样式：内存与 GPU 左右并排竖起来，速度曲线夹在中间，占用一眼见底
    private var dashboardRows: some View {
        VStack(alignment: .leading, spacing: (7 * fontScale).rounded()) {
            headerRow
            speedRow

            // 这一行同时兼作速度图和预填充的蓝色进度条，预填充时整卡仍会漫过蓝色；
            // 多任务沿用最省地方也最好读的多色横向柱状
            Group {
                if state.isPrefilling {
                    Text(prefillBadge())
                        .font(cardFont(9, weight: .semibold).monospacedDigit())
                        .foregroundStyle(prefillTint)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if state.showsTaskCurves {
                    TaskSpeedBars(tasks: liveTasks, scale: fontScale, intensity: level)
                } else {
                    // 波形跟着连接状态变色：推理中绿、加载黄、空闲蓝、离线红，扫一眼就知道卡片还活着没
                    Sparkline(values: state.tpsSeries, tint: Palette.kind(state.kind), intensity: level)
                }
            }
            .frame(height: state.showsTaskCurves && !state.isPrefilling
                ? TaskSpeedBars.height(rows: liveTasks.count, scale: fontScale)
                : (22 * fontScale).rounded())

            HStack(spacing: (7 * fontScale).rounded()) {
                meterTile(
                    title: "内存",
                    fraction: state.memoryFraction,
                    tint: Palette.load(state.memoryFraction),
                    value: memoryPercentText,
                    detail: memoryDetailText,
                    detailTint: inkMid,
                    markers: memoryMarks,
                    status: memoryStatus
                )
                meterTile(
                    title: "GPU",
                    fraction: state.system?.gpuFraction ?? 0,
                    // 表身按 GPU 占用走负荷色带（闲时蓝、跑起来绿、满载橙红），
                    // 温度另走温度色标标在明细里
                    tint: Palette.duty(state.system?.gpuFraction ?? 0),
                    value: gpuPercentText,
                    detail: gpuDetailText,
                    detailTint: Vivid.apply(Palette.temperature(state.system?.peakTemperature), level: level),
                    markers: [],
                    status: gpuStatus
                )
            }
            .frame(height: FloatingCardLayout.meterHeight(fontScale: prefs.cardFontScale))

            HStack {
                Text("今日 \(Fmt.compactTokens(state.todayTotals?.totalTokens)) tok")
                Spacer()
                Text("\(state.todayTotals?.requests ?? 0) 次请求")
            }
            .font(cardFont(9).monospacedDigit())
            .foregroundStyle(inkFaint)
            .lineLimit(1)
        }
    }

    /// 一列竖向仪表：左边自底向上的竖表，右边标签 + 大号百分比 + 明细
    private func meterTile(
        title: String,
        fraction: Double,
        tint: Color,
        value: String,
        detail: String,
        detailTint: Color,
        markers: [MeterMark],
        status: TileStatus?
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9 * fontScale, style: .continuous)
        let alert = status.flatMap { $0.alert ? $0.tint : nil }
        let edge = alert ?? Color.primary
        return HStack(alignment: .top, spacing: (5 * fontScale).rounded()) {
            VerticalMeter(fraction: fraction, tint: tint, markers: markers, intensity: level)
                .frame(width: (14 * fontScale).rounded())
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    Text(title)
                        .font(cardFont(9, weight: .semibold))
                        .foregroundStyle(inkFaint)
                    Spacer(minLength: 2)
                    if let status {
                        Text(status.text)
                            .font(cardFont(8.5, weight: .semibold))
                            .foregroundStyle(status.tint)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                Spacer(minLength: 0)
                Text(value)
                    .font(cardFont(15, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Vivid.apply(tint, level: level))
                    .fixedSize(horizontal: true, vertical: false)
                Text(detail)
                    .font(cardFont(8.5).monospacedDigit())
                    .foregroundStyle(detailTint)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, (7 * fontScale).rounded())
        .padding(.vertical, (5 * fontScale).rounded())
        .frame(maxWidth: .infinity)
        .background(shape.fill(Color.primary.opacity(0.04 + 0.05 * level)))
        .background(shape.fill(alert.map { $0.opacity(0.10 + 0.08 * level) } ?? Color.clear))
        .overlay(
            shape.strokeBorder(
                edge.opacity(alert == nil ? 0.08 + 0.12 * level : 0.5 + 0.3 * level),
                lineWidth: alert == nil ? 0.5 : 0.9
            )
        )
        .clipShape(shape)
        .help("\(title) \(value) \(detail)\(status.map { " " + $0.text } ?? "")")
    }

    private var memoryPercentText: String {
        guard state.memoryMax != nil else { return "—" }
        return "\(Int((state.memoryFraction * 100).rounded()))%"
    }

    /// 瓦数与容量都很长，前一个数去掉单位只留 "61/64 GB"，窄列里才放得下
    private var memoryDetailText: String {
        guard let used = state.memoryUsed, let total = state.memoryMax, total > 0 else { return "内存未知" }
        let usedText = Fmt.compactBytes(used).replacingOccurrences(of: " GB", with: "")
        return "\(usedText)/\(Fmt.compactBytes(total))"
    }

    private var gpuPercentText: String {
        guard let gpu = state.system?.gpuDevice else { return "—" }
        return String(format: "%.0f%%", gpu)
    }

    private var gpuDetailText: String {
        guard let snapshot = state.system, snapshot.hasAnyValue else { return "未采集" }
        var parts: [String] = []
        if let peak = snapshot.peakTemperature { parts.append(String(format: "%.0f°C", peak)) }
        if let power = snapshot.powerTotal { parts.append(String(format: "%.0fW", power)) }
        return parts.isEmpty ? "无数据" : parts.joined(separator: " ")
    }

    /// 内存状态角标：说法与取色都走 MemoryBand 四档，
    /// oMLX 报出硬压力时直接把档位顶到吃紧（那是真信号，不看百分比）
    private var memoryStatus: TileStatus? {
        guard state.memoryMax != nil else { return nil }
        var band = MemoryBand(fraction: state.memoryFraction)
        if state.pressure?.pressureLevel == "hard" { band = .critical }
        return TileStatus(text: band.label, tint: Vivid.apply(band.tint, level: level), alert: band.isAlert)
    }

    /// GPU 状态角标：热力等级 + 按温度取色，偏热起把整格描边点亮
    private var gpuStatus: TileStatus? {
        guard let snapshot = state.system, snapshot.hasAnyValue else { return nil }
        let thermal = snapshot.thermalDisplay
        guard thermal != .unknown else { return nil }
        return TileStatus(
            text: thermal.label,
            tint: Vivid.apply(Palette.temperature(snapshot.peakTemperature), level: level),
            alert: thermal >= .fair
        )
    }

    /// 内存刻度用 oMLX 报的软 / 硬阈值真实位置，并染上各自的告警色；
    /// 两根靠得太近就只留更硬的那根，免得在小表里糊成一条粗线
    private var memoryMarks: [MeterMark] {
        guard let pressure = state.pressure, let total = state.memoryMax, total > 0 else {
            return [MeterMark(fraction: 0.85), MeterMark(fraction: 0.95)]
        }
        var marks: [MeterMark] = []
        if let soft = pressure.softBytes {
            let fraction = Double(soft) / Double(total)
            marks.append(MeterMark(fraction: fraction, tint: MemoryBand(fraction: fraction).tint))
        }
        if let hard = pressure.hardBytes {
            let fraction = Double(hard) / Double(total)
            marks.append(MeterMark(fraction: fraction, tint: MemoryBand(fraction: fraction).tint))
        }
        let sorted = marks.sorted { $0.fraction < $1.fraction }
        guard sorted.count == 2 else { return sorted }
        return sorted[1].fraction - sorted[0].fraction < 0.04 ? Array(sorted[1...]) : sorted
    }

    /// 半透明蓝从左往右漫过整张卡片：卡片本身就是预填充进度条（压在文字下方，保证可读）
    @ViewBuilder
    private var prefillFill: some View {
        if state.isPrefilling {
            GeometryReader { proxy in
                if let fraction = state.prefillFraction {
                    let width = max(3, proxy.size.width * min(max(fraction, 0), 1))
                    prefillBand(width: width)
                        .animation(.easeOut(duration: 0.45), value: width)
                } else {
                    TimelineView(.periodic(from: .now, by: 0.05)) { context in
                        let phase = context.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: 1.8) / 1.8
                        Rectangle()
                            .fill(prefillTint.opacity(0.10 + 0.14 * triangle(phase) + 0.06 * level))
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func prefillBand(width: CGFloat) -> some View {
        ZStack(alignment: .trailing) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            prefillTint.opacity(0.10 + 0.06 * level),
                            prefillTint.opacity(0.32 + 0.18 * level)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            Rectangle()
                .fill(prefillTint.opacity(min(1, 0.85 + 0.15 * level)))
                .frame(width: 2)
        }
        .frame(width: width)
    }

    /// 柱状只列还在吐字的任务，颜色跟着请求走
    private var liveTasks: [TaskSeries] { state.liveTaskSeries }

    /// 样式选了「横向柱状」且确实有多个任务在吐字时才画柱状，否则维持老的速度曲线
    private var showsTaskBars: Bool { state.showsTaskCurves && prefs.cardStyle == .bars }

    /// 只有曲线样式需要图例给曲线对色；柱状每行自带数值，那一行留给内存进度条
    private var showsTaskLegend: Bool { state.showsTaskCurves && prefs.cardStyle == .curves }

    private var taskCurves: [SpeedCurve] {
        state.taskSeries.map { SpeedCurve(id: $0.id, values: $0.values, tint: Palette.task($0.colorIndex)) }
    }

    /// 曲线样式下的多任务图例：颜色点对得上上面的曲线，最多列三条，其余折成 +N
    private func taskLegend() -> some View {
        HStack(spacing: 6) {
            ForEach(Array(liveTasks.prefix(3).enumerated()), id: \.element.id) { _, task in
                HStack(spacing: 3) {
                    Circle()
                        .fill(Vivid.apply(Palette.task(task.colorIndex), level: level))
                        .frame(width: 4 * fontScale, height: 4 * fontScale)
                    Text(Fmt.tps(task.latest))
                        .monospacedDigit()
                }
            }
            if liveTasks.count > 3 {
                Text("+\(liveTasks.count - 3)")
                    .monospacedDigit()
            }
            Text("t/s")
                .font(cardFont(8, weight: .medium))
                .foregroundStyle(inkFaint)
            Spacer(minLength: 0)
        }
        .font(cardFont(9, weight: .semibold))
        .foregroundStyle(inkMid)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func triangle(_ value: Double) -> Double {
        value < 0.5 ? value * 2 : (1 - value) * 2
    }

    private func prefillBadge() -> String {
        let speed = state.prefillSpeed
        if let fraction = state.prefillFraction {
            return speed > 0.5
                ? "预填充 \(Int(fraction * 100))% · \(Fmt.tps(speed)) t/s"
                : "预填充 \(Int(fraction * 100))%"
        }
        return speed > 0.5 ? "预填充 \(Fmt.tps(speed)) t/s" : "预填充中"
    }

    private func gpuBadge(_ snapshot: SystemSnapshot) -> String {
        var parts: [String] = []
        if let gpu = snapshot.gpuDevice { parts.append(String(format: "GPU %.0f%%", gpu)) }
        if let peak = snapshot.peakTemperature { parts.append(String(format: "%.0f°", peak)) }
        return parts.isEmpty ? "—" : parts.joined(separator: " ")
    }
}
