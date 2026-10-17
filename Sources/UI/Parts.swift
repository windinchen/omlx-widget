import AppKit
import SwiftUI

enum Palette {
    /// 预填充（prefill）专用蓝
    static let prefill = Color(red: 0.34, green: 0.66, blue: 0.98)

    static func kind(_ kind: WidgetKind) -> Color {
        switch kind {
        case .offline: return Color(red: 0.90, green: 0.34, blue: 0.32)
        case .busy: return Color(red: 0.30, green: 0.80, blue: 0.55)
        case .loading: return Color(red: 0.98, green: 0.72, blue: 0.25)
        case .idle: return Color(red: 0.45, green: 0.62, blue: 0.92)
        }
    }

    static func pressure(_ level: String?) -> Color {
        switch level {
        case "hard": return Color(red: 0.90, green: 0.34, blue: 0.32)
        case "soft", "warn", "warning": return Color(red: 0.98, green: 0.72, blue: 0.25)
        default: return Color(red: 0.30, green: 0.80, blue: 0.55)
        }
    }

    /// 连续色带：数值在色标之间插值，占用 / 温度一涨颜色就跟着往暖色走，
    /// 不用等跨过某个阈值才整块跳色（三档写法在 73% 这种常态位上永远是一个颜色）
    private static func heat(_ value: Double, stops: [(at: Double, rgb: (Double, Double, Double))]) -> Color {
        guard let head = stops.first, let tail = stops.last, stops.count > 1 else { return Color.primary }
        let clamped = min(max(value, head.at), tail.at)
        var upper = stops.count - 1
        while upper > 1, clamped <= stops[upper - 1].at { upper -= 1 }
        let low = stops[upper - 1]
        let high = stops[upper]
        let ratio = min(max((clamped - low.at) / max(1e-6, high.at - low.at), 0), 1)
        return Color(
            red: low.rgb.0 + (high.rgb.0 - low.rgb.0) * ratio,
            green: low.rgb.1 + (high.rgb.1 - low.rgb.1) * ratio,
            blue: low.rgb.2 + (high.rgb.2 - low.rgb.2) * ratio
        )
    }

    /// 内存取色入口：交给 MemoryBand 四档判定，卡片 / 面板 / 竖表永远同一个颜色
    static func load(_ fraction: Double) -> Color {
        MemoryBand(fraction: fraction).tint
    }

    /// GPU 占用色标（负荷语义，与内存余量相反）：闲时蓝，活一干起来就走青→绿，
    /// 八成以上黄，满载橙红。这样"在不在跑活"扫一眼表身颜色就知道
    private static let dutyStops: [(at: Double, rgb: (Double, Double, Double))] = [
        (0.0, (0.36, 0.68, 0.96)),
        (0.25, (0.27, 0.79, 0.78)),
        (0.55, (0.30, 0.80, 0.55)),
        (0.80, (0.98, 0.78, 0.30)),
        (1.0, (0.98, 0.52, 0.28))
    ]

    static func duty(_ fraction: Double) -> Color {
        heat(fraction, stops: dutyStops)
    }

    /// 温度色标（摄氏度）：40° 蓝 → 60° 绿 → 74° 黄 → 84° 橙 → 94° 红，
    /// 起点压到 40°，机器从 53° 爬到 70° 这一路就看得出来在变热
    private static let temperatureStops: [(at: Double, rgb: (Double, Double, Double))] = [
        (40.0, (0.36, 0.68, 0.96)),
        (60.0, (0.30, 0.80, 0.55)),
        (74.0, (0.98, 0.78, 0.30)),
        (84.0, (0.98, 0.60, 0.28)),
        (94.0, (0.90, 0.34, 0.32))
    ]

    static func temperature(_ celsius: Double?) -> Color {
        guard let celsius else { return Color.primary }
        return heat(celsius, stops: temperatureStops)
    }

    /// 多任务速度曲线的配色，按任务首次出现顺序取色
    static let taskPalette: [Color] = [
        Color(red: 0.31, green: 0.76, blue: 0.97),
        Color(red: 1.00, green: 0.77, blue: 0.24),
        Color(red: 1.00, green: 0.48, blue: 0.67),
        Color(red: 0.65, green: 0.55, blue: 0.98),
        Color(red: 0.18, green: 0.83, blue: 0.75),
        Color(red: 1.00, green: 0.62, blue: 0.27),
        Color(red: 0.64, green: 0.90, blue: 0.21),
        Color(red: 0.49, green: 0.61, blue: 1.00)
    ]

    static func task(_ index: Int) -> Color {
        taskPalette[index % taskPalette.count]
    }
}

/// 内存四档：0–75% 绿（充裕）、76–80% 蓝（正常）、81–90% 黄（偏高）、90% 以上红（吃紧）。
/// 按卡片上显示出来的整数百分比分档，颜色跟那串数字永远对得上，
/// 不会出现"写着 88% 却还是绿的"这类误导
enum MemoryBand {
    case ample
    case normal
    case high
    case critical

    init(fraction: Double) {
        switch (min(max(fraction, 0), 1) * 100).rounded() {
        case ..<76: self = .ample
        case ..<81: self = .normal
        case ..<91: self = .high
        default: self = .critical
        }
    }

    var tint: Color {
        switch self {
        case .ample: return Color(red: 0.30, green: 0.80, blue: 0.55)
        case .normal: return Color(red: 0.36, green: 0.68, blue: 0.96)
        case .high: return Color(red: 0.98, green: 0.78, blue: 0.30)
        case .critical: return Color(red: 0.90, green: 0.34, blue: 0.32)
        }
    }

    var label: String {
        switch self {
        case .ample: return "充裕"
        case .normal: return "正常"
        case .high: return "偏高"
        case .critical: return "吃紧"
        }
    }

    /// 只有红档才把整格底色和描边点亮，黄档只染色，免得常态下卡片一直在闪
    var isAlert: Bool { self == .critical }
}

/// 白天 / 夜晚：显式选了白天或夜晚就照办，只有"跟随系统"才去看系统设置
enum Appearance {
    /// 系统自身的深浅色，不受本 App 覆盖影响；AppleInterfaceStyle 缺失即浅色
    static var systemIsDark: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    /// 卡片当前铺在哪种底色上，调色方向以此为准
    static var isDark: Bool {
        switch Preferences.shared.appearanceMode {
        case .system: return systemIsDark
        case .light: return false
        case .dark: return true
        }
    }

    /// 交给 NSApp 的外观覆盖，跟随系统时交回 nil
    static var override: NSAppearance? {
        switch Preferences.shared.appearanceMode {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    /// 状态栏文字恒定白色，所以把状态项按钮钉在深色外观：
    /// 点开面板时系统画的高亮底色才是深的，白字不会被浅色高亮吞掉
    static var menuBar: NSAppearance {
        NSAppearance(named: .darkAqua) ?? NSAppearance(named: .aqua)!
    }
}

/// 按档位拉开颜色与卡面的对比：0 是原样，1 最强；深色底往纯白提亮，浅色底往纯黑压深
enum Vivid {
    static func apply(_ color: Color, level: Double) -> Color {
        guard level > 0.01 else { return color }
        guard let base = NSColor(color).usingColorSpace(.deviceRGB) else { return color }
        let factor = CGFloat(level)
        let saturation = min(1, base.saturationComponent * (1 + 0.22 * factor))
        let brightness: CGFloat
        if Appearance.isDark {
            brightness = min(1, base.brightnessComponent + (1 - base.brightnessComponent) * 0.45 * factor)
        } else {
            brightness = max(0.14, base.brightnessComponent * (1 - 0.66 * factor))
        }
        return Color(
            NSColor(
                calibratedHue: base.hueComponent,
                saturation: min(1, saturation * (Appearance.isDark ? 1 : 1.12)),
                brightness: brightness,
                alpha: base.alphaComponent
            )
        )
    }
}

struct StatusDot: View {
    var kind: WidgetKind
    var size: CGFloat = 9
    var pulses: Bool = true
    var intensity: Double = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.45, paused: !(pulses && kind == .busy))) { context in
            let wave = sin(context.date.timeIntervalSinceReferenceDate * 4.2)
            Circle()
                .fill(Vivid.apply(Palette.kind(kind), level: intensity))
                .frame(width: size, height: size)
                .scaleEffect(kind == .busy ? 1 + CGFloat(wave) * 0.16 : 1)
                .opacity(kind == .busy ? 0.72 + CGFloat(wave) * 0.28 : 1)
        }
        .frame(width: size, height: size)
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 10
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
    }

    init(padding: CGFloat = 10, @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding
        self.content = content
    }
}

struct SectionLabel: View {
    var title: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
        }
        .foregroundStyle(.secondary)
    }
}

struct MetricRow: View {
    var label: String
    var value: String
    var detail: String?
    var tint: Color?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(tint ?? Color.primary)
            if let detail {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct GaugeBar: View {
    var fraction: Double
    var markers: [Double] = []
    var tint: Color?
    var height: CGFloat = 7
    var intensity: Double = 0

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let clamped = min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10 + 0.12 * intensity))
                Capsule()
                    .fill(Vivid.apply(tint ?? Palette.load(clamped), level: intensity))
                    .frame(width: clamped > 0 ? max(2, width * clamped) : 0)
                ForEach(Array(markers.enumerated()), id: \.offset) { _, marker in
                    Rectangle()
                        .fill(Color.primary.opacity(min(1, 0.45 + 0.35 * intensity)))
                        .frame(width: 1, height: height + 3)
                        .offset(x: width * min(max(marker, 0), 1) - 0.5)
                }
            }
        }
        .frame(height: height)
    }
}

/// 竖表上的一根警戒刻度：位置 + 该位自己的颜色（软阈值黄、硬阈值红）
struct MeterMark {
    var fraction: Double
    var tint: Color?
}

/// 竖向仪表：自底向上填充的胶囊竖表，适合内存 / GPU 这类 0~1 的占用指标。
/// 越满颜色越烫，警戒位用带色的刻度线压在表身上，读高低比看数字更快
struct VerticalMeter: View {
    var fraction: Double
    var tint: Color?
    var markers: [MeterMark] = []
    /// 表盘中线，表身空着的时候也有个高低参照；画在填充之下，满表时不会显乱
    var graduations: [Double] = [0.5]
    var intensity: Double = 0

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let clamped = min(max(fraction, 0), 1)
            let accent = Vivid.apply(tint ?? Palette.load(clamped), level: intensity)
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color.primary.opacity(0.10 + 0.12 * intensity))
                ForEach(Array(graduations.enumerated()), id: \.offset) { _, grade in
                    Rectangle()
                        .fill(Color.primary.opacity(min(1, 0.18 + 0.22 * intensity)))
                        .frame(width: width, height: 1)
                        .offset(y: -(height * min(max(grade, 0), 1)) + 0.5)
                }
                if clamped > 0 {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.55 + 0.15 * intensity), accent],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(height: max(width, height * clamped))
                }
                ForEach(Array(markers.enumerated()), id: \.offset) { _, marker in
                    Rectangle()
                        .fill((marker.tint ?? Color.primary).opacity(min(1, 0.55 + 0.35 * intensity)))
                        .frame(width: width, height: 1)
                        .offset(y: -(height * min(max(marker.fraction, 0), 1)) + 0.5)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

/// 预填充的「涨水」水位：从卡面底部往上灌，水面是一条缓慢起伏的正弦线。
/// 只有 fraction 参与动画（水位平滑上涨），phase 由 TimelineView 逐帧推，不参与动画
struct WaterLevel: Shape {
    var fraction: Double
    var phase: Double = 0
    var wave: Bool = true

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = surface(in: rect)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }

    /// 只含水面那条线，描边用
    func surface(in rect: CGRect) -> Path {
        var path = Path()
        let clamped = min(max(fraction, 0), 1)
        let amp = wave ? min(1.8, max(0.5, rect.height * 0.035)) : 0
        // 快灌满时把水面夹住，免得起伏的亮线探出卡面被圆角切成半根
        let base = min(max(rect.maxY - rect.height * CGFloat(clamped), rect.minY + amp), rect.maxY)
        let steps = 24
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let point = CGPoint(
                x: rect.minX + rect.width * CGFloat(t),
                y: base + amp * CGFloat(sin(2 * .pi * (t * 1.35 + phase)))
            )
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// 水里往上冒的气泡：大小、横向位置、快慢、起跳时机各不相同，冒到水面时胀开变淡碎掉。
/// 位置是 time 的纯函数（不持有状态），配合 TimelineView 逐帧推进，整片裁在水体里
struct WaterBubbles: View {
    var fraction: Double
    var time: Double
    var tint: Color
    var intensity: Double = 0
    var scale: Double = 1
    var count = 16

    var body: some View {
        Canvas { context, size in
            let water = size.height * CGFloat(min(max(fraction, 0), 1))
            guard water > 7 else { return }
            for index in 0..<count {
                let lane = hashUnit(index, 1)
                let radius = (1.3 + hashUnit(index, 2) * 2.4) * scale
                let duration = 1.3 + hashUnit(index, 3) * 1.8
                let offset = hashUnit(index, 4)
                let wobble = (0.9 + hashUnit(index, 5) * 2.2) * scale
                let drift = 0.5 + hashUnit(index, 6) * 1.4
                let travel = (time / duration + offset).truncatingRemainder(dividingBy: 1)
                let center = CGPoint(
                    x: size.width * lane + CGFloat(sin(time * drift + offset * 6)) * wobble,
                    y: size.height - CGFloat(travel) * water
                )
                var radiusNow = radius
                var alpha = (0.22 + 0.34 * intensity) * min(1, travel / 0.1)
                if travel > 0.86 {
                    // 最后一段算它在水面破碎：胀开的同时迅速变淡
                    let burst = (travel - 0.86) / 0.14
                    radiusNow = radius * (1 + 1.9 * burst)
                    alpha *= 1 - 0.55 * burst
                }
                let rect = CGRect(
                    x: center.x - radiusNow, y: center.y - radiusNow,
                    width: radiusNow * 2, height: radiusNow * 2
                )
                let bubble = Path(ellipseIn: rect)
                context.fill(bubble, with: .color(tint.opacity(alpha)))
                context.stroke(
                    bubble,
                    with: .color(tint.opacity(min(1, alpha * 3.0))),
                    lineWidth: 0.9 * scale
                )
            }
        }
        .clipShape(WaterLevel(fraction: fraction, phase: time.truncatingRemainder(dividingBy: 2.4) / 2.4))
        .allowsHitTesting(false)
    }
}

/// 稳定伪随机：同一个 index 永远给同一个 0~1，气泡参数不用存状态也不会每帧重排
private func hashUnit(_ index: Int, _ salt: Int) -> Double {
    let value = sin(Double(index * 37 + salt * 977) * 12.9898) * 43758.5453
    return value - floor(value)
}

struct Sparkline: View {
    var values: [Double]
    var tint: Color = Color(red: 0.30, green: 0.80, blue: 0.55)
    var showsBaseline: Bool = true
    var intensity: Double = 0

    var body: some View {
        Canvas { context, size in
            let cleaned = values.isEmpty ? [0.0] : values
            let peak = max(cleaned.max() ?? 0, 1)
            let isActive = (cleaned.max() ?? 0) > 0.5
            let accent = Vivid.apply(tint, level: intensity)
            let stepX = cleaned.count > 1 ? size.width / CGFloat(cleaned.count - 1) : size.width
            var line = Path()
            var area = Path()
            for (index, value) in cleaned.enumerated() {
                let point = CGPoint(
                    x: CGFloat(index) * stepX,
                    y: size.height - (size.height - 2) * CGFloat(min(max(value / peak, 0), 1)) - 1
                )
                if index == 0 {
                    line.move(to: point)
                    area.move(to: CGPoint(x: point.x, y: size.height))
                    area.addLine(to: point)
                } else {
                    line.addLine(to: point)
                    area.addLine(to: point)
                }
            }
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.closeSubpath()

            if isActive {
                context.fill(
                    area,
                    with: .linearGradient(
                        Gradient(colors: [accent.opacity(0.38), accent.opacity(0.02)]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )
            }
            if showsBaseline {
                var baseline = Path()
                baseline.move(to: CGPoint(x: 0, y: size.height - 0.5))
                baseline.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
                context.stroke(
                    baseline,
                    with: .color(Color.primary.opacity(min(1, (isActive ? 0.10 : 0.16) + 0.16 * intensity))),
                    style: StrokeStyle(lineWidth: 1, dash: isActive ? [] : [2, 3])
                )
            }
            if isActive {
                context.stroke(
                    line,
                    with: .color(accent),
                    style: StrokeStyle(lineWidth: CGFloat(1.6 + 0.6 * intensity), lineCap: .round, lineJoin: .round)
                )
            }
        }
    }
}

/// 多任务速度曲线里的一条
struct SpeedCurve: Identifiable, Equatable {
    var id: String
    var values: [Double]
    var tint: Color
}

/// 多任务时同一张图上画多条速度曲线，右端点小圆点对应图例颜色
struct MultiSparkline: View {
    var curves: [SpeedCurve]
    var showsBaseline: Bool = true
    var intensity: Double = 0
    var lineWidth: CGFloat = 1.5

    var body: some View {
        Canvas { context, size in
            let peak = max(1, curves.map { $0.values.max() ?? 0 }.max() ?? 1)
            if showsBaseline {
                var baseline = Path()
                baseline.move(to: CGPoint(x: 0, y: size.height - 0.5))
                baseline.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
                context.stroke(
                    baseline,
                    with: .color(Color.primary.opacity(min(1, 0.12 + 0.16 * intensity))),
                    style: StrokeStyle(lineWidth: 1, dash: [2, 3])
                )
            }
            let span = max(2, curves.map { $0.values.count }.max() ?? 2)
            let stepX = size.width / CGFloat(span - 1)
            for curve in curves {
                // 只画任务真正在吐字的那一段：前后的零值会让曲线变成一条横贯卡片的分割线
                let lead = curve.values.prefix(while: { $0 <= 0.05 }).count
                let values = Array(curve.values.dropFirst(lead).prefix(while: { $0 > 0.05 }))
                guard let lastValue = values.last else { continue }
                let tint = Vivid.apply(curve.tint, level: intensity)
                if values.count > 1 {
                    var path = Path()
                    for (index, value) in values.enumerated() {
                        let point = CGPoint(
                            x: CGFloat(lead + index) * stepX,
                            y: height(for: value, height: size.height, peak: peak)
                        )
                        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    context.stroke(
                        path,
                        with: .color(tint),
                        style: StrokeStyle(
                            lineWidth: lineWidth + 0.4 * CGFloat(intensity),
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                }
                let headX = min(size.width - 2, CGFloat(lead + values.count - 1) * stepX)
                let head = CGPoint(x: headX, y: height(for: lastValue, height: size.height, peak: peak))
                context.fill(
                    Path(ellipseIn: CGRect(x: head.x - 2, y: head.y - 2, width: 4, height: 4)),
                    with: .color(tint)
                )
            }
        }
    }

    private func height(for value: Double, height total: CGFloat, peak: Double) -> CGFloat {
        total - (total - 2) * CGFloat(min(max(value / peak, 0), 1)) - 1
    }
}

/// 多任务时的速度对比：多条曲线叠在一起难分辨，改成每个任务一行多色横向柱状，
/// 长度按当前最快的任务归一化，数值右对齐成一列，谁在抢算力一眼看得出来
struct TaskSpeedBars: View {
    var tasks: [TaskSeries]
    var scale: CGFloat = 1
    var intensity: Double = 0

    private var ranked: [TaskSeries] { tasks.sorted { $0.latest > $1.latest } }
    private var shown: [TaskSeries] { Array(ranked.prefix(3)) }
    private var overflow: Int { max(0, ranked.count - shown.count) }
    private var peak: Double { max(ranked.first?.latest ?? 0, 1) }

    /// 卡片要给这块区域留的高度：行高 11 + 行距 3，最多三行
    static func height(rows: Int, scale: CGFloat) -> CGFloat {
        let count = min(3, max(1, rows))
        return (CGFloat(count) * 11 * scale + CGFloat(count - 1) * 3 * scale).rounded()
    }

    var body: some View {
        VStack(spacing: 3 * scale) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, task in
                HStack(spacing: 4) {
                    Circle()
                        .fill(Vivid.apply(Palette.task(task.colorIndex), level: intensity))
                        .frame(width: 4 * scale, height: 4 * scale)
                    GaugeBar(
                        fraction: task.latest / peak,
                        tint: Palette.task(task.colorIndex),
                        height: 5 * scale,
                        intensity: intensity
                    )
                    Text(Fmt.tps(task.latest))
                        .font(.system(size: 9 * scale, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Vivid.apply(Palette.task(task.colorIndex), level: intensity))
                        .frame(width: 30 * scale, alignment: .trailing)
                    Text(suffix(for: index))
                        .font(.system(size: 7.5 * scale, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: 14 * scale, alignment: .leading)
                }
                .frame(height: 11 * scale)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// 单位只在最快那行的数值后出现一次，读起来像列头；没跑满三行时多余任务折成 +N
    private func suffix(for index: Int) -> String {
        if index == 0 { return "t/s" }
        if index == shown.count - 1, overflow > 0 { return "+\(overflow)" }
        return " "
    }
}

struct HeatBars: View {
    var values: [Int]
    var currentHour: Int

    var body: some View {
        Canvas { context, size in
            let count = max(values.count, 1)
            let gap: CGFloat = 2
            let barWidth = max(1, (size.width - gap * CGFloat(count - 1)) / CGFloat(count))
            let peak = max(values.max() ?? 1, 1)
            for (index, value) in values.enumerated() {
                let ratio = CGFloat(Double(value) / Double(peak))
                let height = max(2, (size.height - 2) * ratio)
                let rect = CGRect(
                    x: CGFloat(index) * (barWidth + gap),
                    y: size.height - height,
                    width: barWidth,
                    height: height
                )
                let isCurrent = index == currentHour
                context.fill(
                    Path(roundedRect: rect, cornerRadius: min(2, barWidth / 2)),
                    with: .color(isCurrent ? Color.accentColor : Color.primary.opacity(0.28))
                )
            }
        }
    }
}

struct GhostButton: View {
    var title: String
    var systemImage: String?
    var isDisabled: Bool = false
    var showsTitle: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 9))
                }
                if showsTitle {
                    Text(title).font(.system(size: 11))
                }
            }
            .padding(.horizontal, showsTitle ? 8 : 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(isDisabled ? 0.03 : 0.07))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(title)
    }
}
