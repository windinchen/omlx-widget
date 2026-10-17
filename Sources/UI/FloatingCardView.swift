import AppKit
import SwiftUI

/// 浮窗基准尺寸：字号调大时整张卡片等比放大，避免文字被挤断
enum FloatingCardLayout {
    static let baseWidth: CGFloat = 246
    static let baseHeight: CGFloat = 157

    static func factor(_ fontScale: Double) -> CGFloat {
        CGFloat(min(1.4, max(0.8, fontScale)))
    }

    static func size(fontScale: Double) -> NSSize {
        let factor = factor(fontScale)
        return NSSize(width: (baseWidth * factor).rounded(), height: (baseHeight * factor).rounded())
    }

    /// 右上角关闭按钮的命中区，窗口坐标系（原点在左下）；拖动与点击的判定以它为准
    static func closeRect(fontScale: Double, in size: NSSize) -> NSRect {
        let f = factor(fontScale)
        let side = (26 * f).rounded()
        let margin = (4 * f).rounded()
        return NSRect(x: size.width - side - margin, y: size.height - side - margin + 4, width: side, height: side)
    }
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
        VStack(alignment: .leading, spacing: (7 * fontScale).rounded()) {
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

            Group {
                if state.showsTaskCurves {
                    MultiSparkline(curves: taskCurves, intensity: level)
                } else {
                    Sparkline(values: state.tpsSeries, intensity: level)
                }
            }
            .frame(height: (22 * fontScale).rounded())

            // 预填充时这一行换成蓝色进度文案（整张卡片本身就是进度条），高度固定，卡片不会跳动或裁切
            Group {
                if state.isPrefilling {
                    Text(prefillBadge())
                        .font(cardFont(9, weight: .semibold).monospacedDigit())
                        .foregroundStyle(prefillTint)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if state.showsTaskCurves {
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
                    GaugeBar(fraction: snapshot.gpuFraction, height: 3 * fontScale, intensity: level)
                    Text(gpuBadge(snapshot))
                        .foregroundStyle(Vivid.apply(Palette.temperature(snapshot.peakTemperature), level: level))
                        .fixedSize(horizontal: true, vertical: false)
                }
                .font(cardFont(9).monospacedDigit())
                .foregroundStyle(inkFaint)
                .lineLimit(1)
            }
        }
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

    private var taskCurves: [SpeedCurve] {
        state.taskSeries.map { SpeedCurve(id: $0.id, values: $0.values, tint: Palette.task($0.colorIndex)) }
    }

    /// 图例只列还在吐字的任务，颜色顺序与上面的曲线一致
    private var liveTasks: [TaskSeries] { state.liveTaskSeries }

    /// 多任务图例：颜色点对得上上面的曲线，最多列三条，其余折成 +N
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
