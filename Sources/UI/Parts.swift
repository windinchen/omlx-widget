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

    static func load(_ fraction: Double) -> Color {
        if fraction >= 0.95 { return Color(red: 0.90, green: 0.34, blue: 0.32) }
        if fraction >= 0.85 { return Color(red: 0.98, green: 0.72, blue: 0.25) }
        return Color(red: 0.36, green: 0.68, blue: 0.96)
    }

    static func temperature(_ celsius: Double?) -> Color {
        guard let celsius else { return Color.primary }
        if celsius >= 92 { return Color(red: 0.90, green: 0.34, blue: 0.32) }
        if celsius >= 82 { return Color(red: 0.98, green: 0.60, blue: 0.28) }
        if celsius >= 72 { return Color(red: 0.98, green: 0.78, blue: 0.30) }
        return Color(red: 0.36, green: 0.68, blue: 0.96)
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

    /// 菜单栏由系统着色，别让 App 的日夜选择把状态栏文字染成看不见的颜色
    static var menuBar: NSAppearance {
        NSAppearance(named: systemIsDark ? .darkAqua : .aqua) ?? NSAppearance(named: .aqua)!
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
