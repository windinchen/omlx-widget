import AppKit
import SwiftUI

/// 更新说明里出现过的排版：标题、小标题、列表、编号列表、正文、表格行、分隔线
struct NotesLine: Identifiable {
    enum Kind {
        case heading
        case subheading
        case bullet
        case numbered
        case paragraph
        case divider
    }

    var id: Int
    var kind: Kind
    var text: String
    var indent: Int = 0
}

/// 轻量 Markdown 读取器：说明文档只有这几类排版，不值得为它引一个渲染库
enum ReleaseNotesParser {
    /// 安装包里的说明同时写给发布页和装包的人看，"安装 / 校验和"那几段在更新弹窗里只是占地方
    private static let cutMarkers = ["安装", "校验和", "从源码", "构建"]

    static func trim(_ text: String) -> String {
        var kept: [String] = []
        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if index == 0, trimmed.hasPrefix("#") { continue }
            if trimmed.hasPrefix("#"), cutMarkers.contains(where: { trimmed.contains($0) }) {
                while let last = kept.last, isRule(last.trimmingCharacters(in: .whitespaces)) {
                    kept.removeLast()
                }
                break
            }
            kept.append(line)
        }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parse(_ text: String) -> [NotesLine] {
        var lines: [NotesLine] = []
        var blankBefore = true
        for raw in text.components(separatedBy: "\n") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                blankBefore = true
                continue
            }
            // 发布页里的图片在这画不出来，整行丢掉
            if trimmed.hasPrefix("<p") || trimmed.hasPrefix("<img") || trimmed.hasPrefix("</p") { continue }
            if isRule(trimmed) {
                lines.append(NotesLine(id: lines.count, kind: .divider, text: ""))
                blankBefore = false
                continue
            }
            if trimmed.hasPrefix("|") {
                blankBefore = append(trimmed, to: &lines, blankBefore: blankBefore)
                continue
            }
            if let level = headingLevel(trimmed) {
                let title = clean(String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces))
                lines.append(NotesLine(id: lines.count, kind: level >= 3 ? .subheading : .heading, text: title))
                blankBefore = false
                continue
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let indent = raw.prefix(while: { $0 == " " }).count >= 2 ? 1 : 0
                lines.append(
                    NotesLine(id: lines.count, kind: .bullet, text: clean(String(trimmed.dropFirst(2))), indent: indent)
                )
                blankBefore = false
                continue
            }
            if let numbered = numberedItem(trimmed) {
                lines.append(NotesLine(id: lines.count, kind: .numbered, text: clean(numbered)))
                blankBefore = false
                continue
            }
            // 中文说明一段折成好几行：紧跟上一条的续行并回去，空过行的就是新起一段
            if !blankBefore, var last = lines.last, last.kind == .bullet || last.kind == .numbered || last.kind == .paragraph {
                last.text += clean(" " + trimmed)
                lines[lines.count - 1] = last
                continue
            }
            lines.append(NotesLine(id: lines.count, kind: .paragraph, text: clean(trimmed)))
            blankBefore = false
        }
        return lines
    }

    /// 表格行拍平成 "列 · 列"，分隔行扔掉；返回下一次的 blankBefore
    private static func append(_ trimmed: String, to lines: inout [NotesLine], blankBefore: Bool) -> Bool {
        if trimmed.contains("---") { return blankBefore }
        let cells = trimmed
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { clean(String($0).trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
        guard !cells.isEmpty else { return blankBefore }
        lines.append(NotesLine(id: lines.count, kind: .bullet, text: cells.joined(separator: " · ")))
        return false
    }

    private static func isRule(_ trimmed: String) -> Bool {
        guard trimmed.count >= 3 else { return false }
        return trimmed.allSatisfy { $0 == "-" } || trimmed.allSatisfy { $0 == "*" }
    }

    private static func headingLevel(_ line: String) -> Int? {
        guard line.hasPrefix("#") else { return nil }
        let level = line.prefix(while: { $0 == "#" }).count
        guard level <= 6, line.count > level else { return nil }
        let next = line[line.index(line.startIndex, offsetBy: level)]
        return next == " " ? level : nil
    }

    private static func numberedItem(_ line: String) -> String? {
        guard let dot = line.firstIndex(of: "."), line[line.startIndex..<dot].allSatisfy(\.isNumber),
              !line[line.startIndex..<dot].isEmpty else { return nil }
        let after = line.index(after: dot)
        guard after < line.endIndex, line[after] == " " else { return nil }
        return String(line[line.index(after: after)...])
    }

    /// 只扔 HTML 标签（发布页专用的 img / p 在这里画不出来），
    /// 加粗、行内代码、链接交给 SwiftUI 的 Markdown 行内解析去还原
    private static func clean(_ text: String) -> String {
        var result = text
        while let tag = result.firstIndex(of: "<"), let end = result.firstIndex(of: ">"), tag < end {
            result.removeSubrange(tag...end)
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}

/// 更新弹窗要展示的一份内容：标题、副标题、正文说明、下载与主页链接
struct UpdateReport {
    var headline: String
    var subline: String
    var symbol: String
    var tint: Color
    var notes: String
    var downloadURL: URL?
    var pageURL: URL?
    var showsNotes: Bool = true
}

struct UpdateView: View {
    var report: UpdateReport

    private var lines: [NotesLine] { ReleaseNotesParser.parse(report.notes) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 8) {
                    if report.showsNotes {
                        ForEach(lines) { line in row(line) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 6)
            }
            .frame(maxHeight: 360)
            footer
        }
        .padding(16)
        .frame(width: 460, height: 520)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: report.symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(report.tint)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(report.tint.opacity(0.16)))
            VStack(alignment: .leading, spacing: 3) {
                Text(report.headline)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text(report.subline)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("本机 v\(AppVersion.current.description) · 更新说明自动读自安装包与 GitHub Release")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func row(_ line: NotesLine) -> some View {
        let pad = CGFloat(line.indent) * 12
        switch line.kind {
        case .heading:
            Text(line.text)
                .font(.system(size: 14, weight: .bold))
                .padding(.top, 4)
        case .subheading:
            Text(line.text)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 2)
        case .bullet:
            HStack(alignment: .top, spacing: 6) {
                Text("•").font(.system(size: 11)).foregroundStyle(.secondary)
                note(line.text).font(.system(size: 11.5)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, pad)
        case .numbered:
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "circle").font(.system(size: 5)).foregroundStyle(.secondary)
                note(line.text).font(.system(size: 11.5)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, pad)
        case .paragraph:
            note(line.text)
                .font(.system(size: 11.5))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, pad)
        case .divider:
            Divider().padding(.vertical, 2)
        }
    }

    /// 加粗、行内代码、链接交给系统的行内 Markdown 解析还原，别自己糊
    private func note(_ text: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard let attributed = try? AttributedString(markdown: text, options: options) else { return Text(text) }
        return Text(attributed)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if let download = report.downloadURL {
                GhostButton(title: "下载新版本", systemImage: "arrow.down.circle") {
                    NSWorkspace.shared.open(download)
                }
            }
            if let page = report.pageURL {
                GhostButton(title: "GitHub 发布页", systemImage: "safari") {
                    NSWorkspace.shared.open(page)
                }
            }
            Spacer(minLength: 4)
            Button("知道了") {
                // closeUpdateWindow() 是 @MainActor 隔离的；Xcode 15 的 SDK 里 SwiftUI 的
                // action 闭包不带隔离，直接调用在 CI 上编不过（本机新工具链会放过）
                Task { @MainActor in AppController.shared?.closeUpdateWindow() }
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}

@MainActor
final class UpdateWindowController: NSWindowController {
    private let model = UpdateWindowModel()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "oMLX 小工具 · 更新"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        self.init(window: window)
        // 视图要持有同一份 model，只能等 self.init 之后再挂上去
        window.contentViewController = NSHostingController(rootView: UpdateContainer(model: model))
        window.center()
    }

    /// 弹窗内容随检查结果变，尺寸固定，免得每次打开都在屏幕上跳一下
    func present(_ report: UpdateReport) {
        model.report = report
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class UpdateWindowModel: ObservableObject {
    @Published var report: UpdateReport?
}

struct UpdateContainer: View {
    @ObservedObject var model: UpdateWindowModel

    var body: some View {
        if let report = model.report {
            UpdateView(report: report)
        } else {
            Color.clear.frame(width: 460, height: 520)
        }
    }
}
