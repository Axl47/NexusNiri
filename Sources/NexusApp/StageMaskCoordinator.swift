import AppKit
import SharedTypes
import StageChrome

@MainActor
protocol StageMaskCoordinating {
    func attach(to window: NSWindow?)
    func update(
        layout: LayoutPlan?,
        stageViewportFrame: CGRect?,
        shellDisplayLayout: ShellDisplayLayout?,
        shellPresentationMode: ShellPresentationMode
    )
    func hideAll()
}

@MainActor
final class NoopStageMaskCoordinator: StageMaskCoordinating {
    func attach(to window: NSWindow?) {}
    func update(
        layout: LayoutPlan?,
        stageViewportFrame: CGRect?,
        shellDisplayLayout: ShellDisplayLayout?,
        shellPresentationMode: ShellPresentationMode
    ) {}
    func hideAll() {}
}

@MainActor
final class StageMaskCoordinator: StageMaskCoordinating {
    private var sidebarWindow: NSWindow?
    private var topbarWindow: NSWindow?
    private var topLeftAuxiliaryWindow: NSWindow?
    private var topRightAuxiliaryWindow: NSWindow?
    private var headerWindow: NSWindow?
    private var indicatorWindow: NSWindow?
    private weak var parentWindow: NSWindow?

    func attach(to window: NSWindow?) {
        guard parentWindow !== window else { return }

        if let parentWindow {
            chromeWindows.forEach { parentWindow.removeChildWindow($0) }
        }

        parentWindow = window

        guard let window else { return }

        chromeWindows.forEach { window.addChildWindow($0, ordered: .below) }
    }

    func update(
        layout: LayoutPlan?,
        stageViewportFrame: CGRect?,
        shellDisplayLayout: ShellDisplayLayout?,
        shellPresentationMode: ShellPresentationMode
    ) {
        _ = layout
        guard let stageViewportFrame else {
            hideAll()
            return
        }

        ensureSidebarWindow()
        ensureTopbarWindow()
        ensureTopLeftAuxiliaryWindow()
        ensureTopRightAuxiliaryWindow()
        ensureHeaderWindow()
        ensureIndicatorWindow()

        guard let parentWindow else { return }

        let frames: [(NSWindow?, CGRect?)] =
            if shellPresentationMode == .notchFill {
                [
                    (sidebarWindow, nil),
                    (topbarWindow, nil),
                    (topLeftAuxiliaryWindow, shellDisplayLayout?.topLeftAuxiliaryFrame?.integral),
                    (topRightAuxiliaryWindow, shellDisplayLayout?.topRightAuxiliaryFrame?.integral),
                    (headerWindow, headerFrame(for: stageViewportFrame)),
                    (indicatorWindow, indicatorFrame(for: stageViewportFrame)),
                ]
            } else {
                [
                    (sidebarWindow, sidebarFrame(for: parentWindow)),
                    (topbarWindow, topbarFrame(for: stageViewportFrame)),
                    (topLeftAuxiliaryWindow, nil),
                    (topRightAuxiliaryWindow, nil),
                    (headerWindow, headerFrame(for: stageViewportFrame)),
                    (indicatorWindow, indicatorFrame(for: stageViewportFrame)),
                ]
            }

        for (window, frame) in frames {
            guard let window else { continue }
            guard let frame else {
                window.orderOut(nil)
                continue
            }
            window.setFrame(frame.integral, display: true)
            if window.parent == nil {
                parentWindow.addChildWindow(window, ordered: .below)
            }
            window.orderFront(nil)
        }
    }

    func hideAll() {
        chromeWindows.forEach { $0.orderOut(nil) }
    }

    private func ensureSidebarWindow() {
        guard sidebarWindow == nil else { return }
        sidebarWindow = makeWindow()
    }

    private func ensureTopbarWindow() {
        guard topbarWindow == nil else { return }
        topbarWindow = makeWindow()
    }

    private func ensureHeaderWindow() {
        guard headerWindow == nil else { return }
        headerWindow = makeWindow()
    }

    private func ensureTopLeftAuxiliaryWindow() {
        guard topLeftAuxiliaryWindow == nil else { return }
        topLeftAuxiliaryWindow = makeWindow()
    }

    private func ensureTopRightAuxiliaryWindow() {
        guard topRightAuxiliaryWindow == nil else { return }
        topRightAuxiliaryWindow = makeWindow()
    }

    private func ensureIndicatorWindow() {
        guard indicatorWindow == nil else { return }
        indicatorWindow = makeWindow()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = true
        window.hasShadow = false
        window.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1.0)
        window.level = .floating
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        return window
    }

    private func sidebarFrame(for window: NSWindow) -> CGRect? {
        guard let contentView = window.contentView else { return nil }
        let rectInWindow = contentView.convert(contentView.bounds, to: nil)
        let contentRect = window.convertToScreen(rectInWindow)
        return CGRect(
            x: contentRect.minX,
            y: contentRect.minY,
            width: ChromeMetrics.sidebarWidth,
            height: contentRect.height
        )
    }

    private func topbarFrame(for stageViewportFrame: CGRect) -> CGRect? {
        CGRect(
            x: stageViewportFrame.minX,
            y: stageViewportFrame.maxY,
            width: stageViewportFrame.width,
            height: ChromeMetrics.topbarHeight
        )
    }

    private func headerFrame(for stageViewportFrame: CGRect) -> CGRect? {
        CGRect(
            x: stageViewportFrame.minX,
            y: stageViewportFrame.maxY - ChromeMetrics.slotHeaderHeight,
            width: stageViewportFrame.width,
            height: ChromeMetrics.slotHeaderHeight
        )
    }

    private func indicatorFrame(for stageViewportFrame: CGRect) -> CGRect? {
        CGRect(
            x: stageViewportFrame.minX,
            y: stageViewportFrame.minY,
            width: stageViewportFrame.width,
            height: ChromeMetrics.stripIndicatorHeight
        )
    }

    private var chromeWindows: [NSWindow] {
        [
            sidebarWindow,
            topbarWindow,
            topLeftAuxiliaryWindow,
            topRightAuxiliaryWindow,
            headerWindow,
            indicatorWindow,
        ].compactMap { $0 }
    }
}
