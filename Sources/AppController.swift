import AppKit
import SwiftUI
import Combine

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// SwiftUI 的 hosting view 会吃掉 mouseDown，isMovableByWindowBackground 失效，
    /// 这里手动实现"按住卡片任意处拖动"：按下照常转发给按钮，真拖起来才移动窗口并吞掉抬起
    private var anchor: NSPoint?
    private var originAtAnchor: NSPoint?
    private var dragging = false

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            dragging = false
            anchor = NSEvent.mouseLocation
            originAtAnchor = frame.origin
            return
        case .leftMouseDragged:
            guard let anchor, let origin = originAtAnchor else { break }
            let pointer = NSEvent.mouseLocation
            if dragging || hypot(pointer.x - anchor.x, pointer.y - anchor.y) > 3 {
                dragging = true
                NSCursor.openHand.set()
                moveTo(pointer, anchor: anchor, origin: origin)
            }
            return
        case .leftMouseUp:
            let point = event.locationInWindow
            anchor = nil
            originAtAnchor = nil
            if dragging {
                dragging = false
                NSCursor.arrow.set()
            } else if FloatingCardLayout.closeRect(fontScale: Preferences.shared.cardFontScale, in: frame.size).contains(point) {
                // 没拖动且落在右上角关闭区才算关闭
                Preferences.shared.showFloatingCard = false
            }
            return
        default:
            break
        }
        super.sendEvent(event)
    }

    /// 卡片贴着指针走，同时不允许拖到所有屏幕可视区之外
    private func moveTo(_ pointer: NSPoint, anchor: NSPoint, origin: NSPoint) {
        let target = NSPoint(x: origin.x + (pointer.x - anchor.x), y: origin.y + (pointer.y - anchor.y))
        let bounds = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.visibleFrame) }
        guard bounds != .zero else {
            setFrameOrigin(target)
            return
        }
        let size = frame.size
        setFrameOrigin(NSPoint(
            x: min(max(target.x, bounds.minX), max(bounds.minX, bounds.maxX - size.width)),
            y: min(max(target.y, bounds.minY), max(bounds.minY, bounds.maxY - size.height))
        ))
    }
}

@MainActor
final class FloatingPanelController {
    private var panel: FloatingPanel?
    private var observers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()

    /// 卡片尺寸跟着字号与样式设置走
    private static func cardSize(fontScale: Double) -> NSSize {
        FloatingCardLayout.size(fontScale: fontScale, style: Preferences.shared.cardStyle)
    }

    /// 重新量尺寸时顶边保持不动，卡片只往上长，不会把用户摆好的位置挪走
    private static func resize(_ panel: FloatingPanel, fontScale: Double) {
        var frame = panel.frame
        let topEdge = frame.maxY
        frame.size = cardSize(fontScale: fontScale)
        frame.origin.y = topEdge - frame.height
        panel.setFrame(frame, display: true, animate: true)
    }

    func show(topmost: Bool) {
        if panel == nil {
            let size = Self.cardSize(fontScale: Preferences.shared.cardFontScale)
            let panel = FloatingPanel(
                contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.contentViewController = NSHostingController(rootView: FloatingCardView())
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            // 拖动由 FloatingPanel.sendEvent 自己处理，避免两套逻辑叠加
            panel.isMovableByWindowBackground = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.isExcludedFromWindowsMenu = true
            if let saved = decode(Preferences.shared.floatingFrame), Self.onScreen(saved) {
                // 只沿用记住的位置，尺寸一律跟当前内容走，避免旧存档把卡片裁切
                var frame = saved
                let topEdge = frame.maxY
                frame.size = size
                frame.origin.y = topEdge - frame.height
                panel.setFrame(frame, display: false)
            } else {
                panel.setContentSize(size)
                panel.setFrameTopLeftPoint(defaultOrigin(size: size))
            }
            trackMoves(of: panel)
            self.panel = panel
        }
        panel?.level = topmost ? .floating : .normal
        panel?.orderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func defaultOrigin(size: NSSize) -> NSPoint {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)
        return NSPoint(x: visible.maxX - size.width - 20, y: visible.maxY - 14)
    }

    /// 换显示器后存下来的坐标可能跑到屏幕外，这时按默认位置重摆
    private static func onScreen(_ frame: NSRect) -> Bool {
        let probe = NSRect(
            x: frame.minX + min(30, frame.width / 2),
            y: frame.minY + min(30, frame.height / 2),
            width: 1,
            height: 1
        )
        return NSScreen.screens.contains { $0.frame.intersects(probe) }
    }

    private func repositionIfNeeded(_ panel: FloatingPanel) {
        let frame = panel.frame
        let center = NSPoint(x: frame.midX, y: frame.midY)
        guard !NSScreen.screens.contains(where: { $0.frame.contains(center) }) else { return }
        let screen = NSScreen.screens.min(by: {
            distance($0.visibleFrame, center) < distance($1.visibleFrame, center)
        }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? frame
        var origin = frame.origin
        origin.x = min(max(visible.minX, origin.x), max(visible.minX, visible.maxX - frame.width))
        origin.y = min(max(visible.minY, origin.y), max(visible.minY, visible.maxY - frame.height))
        panel.setFrameOrigin(origin)
    }

    private func distance(_ rect: NSRect, _ point: NSPoint) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }

    private func trackMoves(of panel: FloatingPanel) {
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            let observer = NotificationCenter.default.addObserver(forName: name, object: panel, queue: .main) { _ in
                let frame = panel.frame
                Task { @MainActor [weak controller = self] in
                    controller?.persist(frame)
                }
            }
            observers.append(observer)
        }
        let screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak controller = self] in
                controller?.repositionIfNeeded(panel)
            }
        }
        observers.append(screenObserver)

        // 字号滑块改动后即时重设卡片大小，顶边保持不动
        Preferences.shared.$cardFontScale
            .removeDuplicates()
            .sink { [weak panel] scale in
                Task { @MainActor in
                    guard let panel else { return }
                    Self.resize(panel, fontScale: scale)
                }
            }
            .store(in: &cancellables)

        // 换样式时卡片高度会变（竖向仪表更高），同样顶边不动重新量一次
        Preferences.shared.$cardStyle
            .removeDuplicates()
            .sink { [weak panel] _ in
                Task { @MainActor in
                    guard let panel else { return }
                    Self.resize(panel, fontScale: Preferences.shared.cardFontScale)
                }
            }
            .store(in: &cancellables)
    }

    private func persist(_ frame: NSRect) {
        Preferences.shared.floatingFrame = "\(frame.origin.x) \(frame.origin.y) \(frame.width) \(frame.height)"
    }

    private func decode(_ raw: String?) -> NSRect? {
        guard let raw else { return nil }
        let parts = raw.split(separator: " ").compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        return NSRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    convenience init() {
        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "oMLX 小工具 设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    nonisolated(unsafe) static private(set) var shared: AppController?

    private let state = WidgetState.shared
    private let prefs = Preferences.shared
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private lazy var floatingController = FloatingPanelController()
    private lazy var settingsController = SettingsWindowController()
    private var cancellables = Set<AnyCancellable>()
    private var appliedDark: Bool?

    override init() {
        super.init()
        AppController.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        item.button?.toolTip = "oMLX 状态小工具"
        statusItem = item
        applyAppearance()

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PopoverView())
        popover.contentSize = NSSize(width: 372, height: 560)
        self.popover = popover

        bindState()
        state.start()
        syncFloating()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        togglePopover()
        return true
    }

    private func bindState() {
        state.$menuBarTitle
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshStatusItem() }
            .store(in: &cancellables)

        prefs.$showFloatingCard
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncFloating() }
            .store(in: &cancellables)

        prefs.$floatingTopmost
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncFloating() }
            .store(in: &cancellables)

        prefs.$appearanceMode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyAppearance() }
            .store(in: &cancellables)

        // "跟随系统"时系统换了深浅色得跟上：AppKit 没公开 NSApplication 的外观变更通知，用系统设置那条分布式通知
        _ = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in AppController.shared?.applyAppearance() }
        }

        refreshStatusItem()
    }

    /// 切白天 / 夜晚：整 App 外观、状态栏图标、依赖深浅色的调色方向一起更新
    private func applyAppearance() {
        NSApp.appearance = Appearance.override
        statusItem?.button?.appearance = Appearance.menuBar
        let dark = Appearance.isDark
        guard appliedDark != dark else { return }
        appliedDark = dark
        // 调色方向变了，让卡片与面板按新方向重画
        prefs.objectWillChange.send()
    }

    private func syncFloating() {
        if prefs.showFloatingCard {
            floatingController.show(topmost: prefs.floatingTopmost)
        } else {
            floatingController.close()
        }
    }

    private func refreshStatusItem() {
        guard let button = statusItem?.button else { return }
        let color = NSColor(Palette.kind(state.kind))
        button.imagePosition = prefs.menuBarMode == .speed ? .noImage : .imageLeading

        if prefs.menuBarMode != .speed {
            let configuration = NSImage.SymbolConfiguration(pointSize: 7, weight: .bold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
            let image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: state.kind.label)?
                .withSymbolConfiguration(configuration)
            image?.isTemplate = false
            button.image = image
        } else {
            button.image = nil
        }

        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .medium)
        // 状态栏文字恒定白色，跟系统菜单项一致，不受 App 日夜切换和浅色 labelColor 影响
        let ink: NSColor = state.kind == .offline ? NSColor.white.withAlphaComponent(0.55) : .white
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: ink,
        ]
        button.attributedTitle = NSAttributedString(string: state.menuBarTitle, attributes: attributes)

        var tooltip = "oMLX · \(state.kind.label)"
        if state.isOnline {
            tooltip += "\n模型 \(state.loadedCount) 个已加载 · 内存 \(Fmt.bytes(state.memoryUsed))/\(Fmt.bytes(state.memoryMax))"
            tooltip += "\n今日 \(Fmt.compactTokens(state.todayTotals?.totalTokens)) tokens · \(state.todayTotals?.requests ?? 0) 次请求"
        } else if let error = state.lastError {
            tooltip += "\n\(error)"
        }
        button.toolTip = tooltip
    }

    @objc private func statusItemClicked(_ sender: NSStatusItem) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseDown || event?.type == .rightMouseUp {
            showMenu()
            return
        }
        togglePopover()
    }

    private func showMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: "立即刷新", action: #selector(menuRefresh), keyEquivalent: "r").target = self
        menu.addItem(withTitle: "发送测速请求", action: #selector(menuProbe), keyEquivalent: "").target = self
        menu.addItem(.separator())

        let floating = NSMenuItem(title: "桌面浮窗", action: #selector(menuToggleFloating), keyEquivalent: "")
        floating.target = self
        floating.state = prefs.showFloatingCard ? .on : .off
        menu.addItem(floating)

        let topmost = NSMenuItem(title: "浮窗置顶", action: #selector(menuToggleTopmost), keyEquivalent: "")
        topmost.target = self
        topmost.state = prefs.floatingTopmost ? .on : .off
        topmost.isEnabled = prefs.showFloatingCard
        menu.addItem(topmost)

        menu.addItem(.separator())
        menu.addItem(withTitle: "打开控制台", action: #selector(menuOpenDashboard), keyEquivalent: "d").target = self
        menu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 oMLX 小工具", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            Task { await state.refresh() }
        }
    }

    @objc private func menuRefresh() {
        Task { await state.refresh() }
    }

    @objc private func menuProbe() {
        Task { await state.runSpeedProbe() }
    }

    @objc private func menuToggleFloating() {
        prefs.showFloatingCard.toggle()
    }

    @objc private func menuToggleTopmost() {
        prefs.floatingTopmost.toggle()
    }

    @objc private func menuOpenDashboard() {
        if let url = state.dashboardURL() {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func showSettings() {
        settingsController.present()
    }

    func popoverWillShow(_ notification: Notification) {
        Task { await state.refresh() }
    }
}
