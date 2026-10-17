// 生成 App 图标：照桌面浮窗的样子画——深色卡面 + 蓝色预填充漫过 + 三条不同颜色的任务速度曲线
// 用法: xcrun swiftc Tools/make-icon.swift -o /tmp/make-icon && /tmp/make-icon /tmp/AppIcon-1024.png
import CoreGraphics
import Foundation
import ImageIO

let side = 1024
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
let space = CGColorSpaceCreateDeviceRGB()

func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a]) ?? CGColor(red: r, green: g, blue: b, alpha: a)
}

guard let ctx = CGContext(
    data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write("无法创建位图上下文\n".data(using: .utf8)!)
    exit(1)
}
ctx.interpolationQuality = .high
ctx.setShouldAntialias(true)

// 卡面：macOS 图标的圆角方框，占画布 80%
let inset = CGFloat(side) * 0.10
let card = CGRect(x: inset, y: inset, width: CGFloat(side) - inset * 2, height: CGFloat(side) - inset * 2)
let radius = CGFloat(side) * 0.18
let cardPath = CGPath(roundedRect: card, cornerWidth: radius, cornerHeight: radius, transform: nil)

ctx.addPath(cardPath)
ctx.setFillColor(color(0.11, 0.12, 0.14))
ctx.fillPath()

ctx.saveGState()
ctx.addPath(cardPath)
ctx.clip()

if let gradient = CGGradient(
    colorsSpace: space,
    colors: [color(0.24, 0.26, 0.29), color(0.09, 0.10, 0.12)] as CFArray,
    locations: [0, 1]
) {
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: card.midX, y: card.maxY),
        end: CGPoint(x: card.midX, y: card.minY),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
}

// 预填充：半透明蓝从左往右漫过大半张卡面，右沿一条亮蓝进度头
let fillWidth = card.width * 0.46
ctx.setFillColor(color(0.24, 0.55, 1.0, 0.20))
ctx.fill(CGRect(x: card.minX, y: card.minY, width: fillWidth, height: card.height))
ctx.setFillColor(color(0.44, 0.71, 1.0, 0.95))
ctx.fill(CGRect(x: card.minX + fillWidth - CGFloat(side) * 0.004, y: card.minY,
                width: CGFloat(side) * 0.008, height: card.height))
ctx.restoreGState()

// 描边
ctx.addPath(cardPath)
ctx.setStrokeColor(color(1, 1, 1, 0.10))
ctx.setLineWidth(CGFloat(side) * 0.008)
ctx.strokePath()

// plot 区域：三条任务曲线共用一条时间轴
let plot = CGRect(x: card.minX + card.width * 0.10, y: card.minY + card.height * 0.26,
                  width: card.width * 0.80, height: card.height * 0.46)

func point(_ x: Double, _ y: Double) -> CGPoint {
    CGPoint(x: plot.minX + plot.width * CGFloat(x), y: plot.minY + plot.height * CGFloat(y))
}

func curve(_ values: [(Double, Double)], tint: CGColor, weight: Double) {
    ctx.setLineDash(phase: 0, lengths: [])
    ctx.setStrokeColor(tint)
    ctx.setFillColor(tint)
    ctx.setLineWidth(CGFloat(weight) * CGFloat(side) * 0.001)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.beginPath()
    ctx.move(to: point(values[0].0, values[0].1))
    for value in values.dropFirst() { ctx.addLine(to: point(value.0, value.1)) }
    ctx.strokePath()
    guard let last = values.last else { return }
    let head = point(last.0, last.1)
    let dot = CGFloat(side) * CGFloat(weight) * 0.001 * 1.15
    ctx.fillEllipse(in: CGRect(x: head.x - dot / 2, y: head.y - dot / 2, width: dot, height: dot))
}

// 基线
ctx.saveGState()
ctx.setLineDash(phase: 0, lengths: [CGFloat(side) * 0.012, CGFloat(side) * 0.018])
ctx.setStrokeColor(color(1, 1, 1, 0.22))
ctx.setLineWidth(CGFloat(side) * 0.004)
ctx.beginPath()
ctx.move(to: CGPoint(x: plot.minX, y: plot.minY))
ctx.addLine(to: CGPoint(x: plot.maxX, y: plot.minY))
ctx.strokePath()
ctx.restoreGState()

curve([(0.00, 0.52), (0.13, 0.72), (0.27, 0.60), (0.42, 0.84), (0.56, 0.66), (0.71, 0.78), (0.86, 0.62)],
      tint: color(0.36, 0.89, 0.61), weight: 26)
curve([(0.16, 0.18), (0.32, 0.34), (0.49, 0.26), (0.66, 0.44), (0.83, 0.36), (1.00, 0.50)],
      tint: color(0.31, 0.76, 0.97), weight: 20)
curve([(0.34, 0.06), (0.52, 0.16), (0.70, 0.08), (0.88, 0.20), (1.00, 0.14)],
      tint: color(1.00, 0.77, 0.24), weight: 20)

guard let image = ctx.makeImage() else {
    FileHandle.standardError.write("无法生成位图\n".data(using: .utf8)!)
    exit(1)
}
guard let destination = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: outPath) as CFURL, "public.png" as CFString, 1, nil
) else {
    FileHandle.standardError.write("无法创建 PNG 输出\n".data(using: .utf8)!)
    exit(1)
}
CGImageDestinationAddImage(destination, image, nil)
if !CGImageDestinationFinalize(destination) {
    FileHandle.standardError.write("写入 PNG 失败\n".data(using: .utf8)!)
    exit(1)
}
print("已生成 \(outPath)")
