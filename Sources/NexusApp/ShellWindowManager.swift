import AppKit
import CoreGraphics
import SharedTypes

@MainActor
protocol ShellWindowManaging {
    func attach(window: NSWindow?)
    func apply(mode: ShellPresentationMode, screen: NSScreen?)
    func currentLayout() -> ShellDisplayLayout?
}

@MainActor
final class ShellWindowManager: ShellWindowManaging {
    private weak var window: NSWindow?
    private var currentMode: ShellPresentationMode = .windowed
    private var currentDisplayLayout: ShellDisplayLayout?
    private var savedWindowedFrame: CGRect?
    private var savedWindowedStyleMask: NSWindow.StyleMask?
    private var savedWindowedCollectionBehavior: NSWindow.CollectionBehavior?
    private var savedWindowedIsMovable: Bool?

    func attach(window: NSWindow?) {
        self.window = window

        guard let window else {
            currentDisplayLayout = nil
            savedWindowedFrame = nil
            savedWindowedStyleMask = nil
            savedWindowedCollectionBehavior = nil
            savedWindowedIsMovable = nil
            return
        }

        if currentMode == .windowed {
            captureWindowedStateIfNeeded(from: window)
            currentDisplayLayout = makeWindowedLayout(for: window)
        }
    }

    func apply(mode: ShellPresentationMode, screen: NSScreen?) {
        currentMode = mode

        guard let window else {
            currentDisplayLayout = nil
            return
        }

        let resolvedScreen = screen ?? window.screen ?? NSScreen.main

        switch mode {
        case .windowed:
            restoreWindowedState(on: window)
            currentDisplayLayout = makeWindowedLayout(for: window)
        case .notchFill:
            captureWindowedStateIfNeeded(from: window)
            applyNotchFill(to: window, screen: resolvedScreen)
            currentDisplayLayout = resolvedScreen.map(makeNotchFillLayout(for:))
        }
    }

    func currentLayout() -> ShellDisplayLayout? {
        currentDisplayLayout
    }

    private func captureWindowedStateIfNeeded(from window: NSWindow) {
        savedWindowedFrame = window.frame
        savedWindowedStyleMask = window.styleMask
        savedWindowedCollectionBehavior = window.collectionBehavior
        savedWindowedIsMovable = window.isMovable
    }

    private func restoreWindowedState(on window: NSWindow) {
        if let savedWindowedStyleMask {
            window.styleMask = savedWindowedStyleMask
        }
        if let savedWindowedCollectionBehavior {
            window.collectionBehavior = savedWindowedCollectionBehavior
        }
        if let savedWindowedIsMovable {
            window.isMovable = savedWindowedIsMovable
        }
        if let savedWindowedFrame, window.frame.integral != savedWindowedFrame.integral {
            window.setFrame(savedWindowedFrame, display: true)
        }

        NSApp.presentationOptions = []
    }

    private func applyNotchFill(to window: NSWindow, screen: NSScreen?) {
        guard let screen else {
            currentDisplayLayout = makeWindowedLayout(for: window)
            return
        }

        NSApp.presentationOptions = [.autoHideDock, .autoHideMenuBar]
        window.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        window.styleMask = [.borderless]
        window.isMovable = false

        let targetFrame = screen.frame.integral
        if window.frame.integral != targetFrame {
            window.setFrame(targetFrame, display: true)
        }
    }

    private func makeWindowedLayout(for window: NSWindow) -> ShellDisplayLayout {
        ShellDisplayLayout(
            windowFrame: window.frame.integral,
            safeContentFrame: window.frame.integral,
            hasCameraHousing: false
        )
    }

    private func makeNotchFillLayout(for screen: NSScreen) -> ShellDisplayLayout {
        let screenFrame = screen.frame.integral
        let safeAreaInsets = screen.safeAreaInsets
        let safeContentFrame = CGRect(
            x: screenFrame.minX + safeAreaInsets.left,
            y: screenFrame.minY + safeAreaInsets.bottom,
            width: screenFrame.width - safeAreaInsets.left - safeAreaInsets.right,
            height: screenFrame.height - safeAreaInsets.top - safeAreaInsets.bottom
        ).integral

        let normalizedTopLeftArea = screen.auxiliaryTopLeftArea.flatMap { area in
            area.isEmpty ? nil : area.integral
        }
        let normalizedTopRightArea = screen.auxiliaryTopRightArea.flatMap { area in
            area.isEmpty ? nil : area.integral
        }

        return ShellDisplayLayout(
            windowFrame: screenFrame,
            safeContentFrame: safeContentFrame,
            topLeftAuxiliaryFrame: normalizedTopLeftArea,
            topRightAuxiliaryFrame: normalizedTopRightArea,
            hasCameraHousing: normalizedTopLeftArea != nil || normalizedTopRightArea != nil
        )
    }
}

enum ShellPresentationPersistence {
    static let globalKey = "nexus.shellPresentationMode.default"
    static let displayPrefix = "nexus.shellPresentationMode.display"

    static func key(for screen: NSScreen?) -> String {
        guard let screen, let displayIdentifier = builtInDisplayIdentifier(for: screen) else {
            return globalKey
        }

        return "\(displayPrefix).\(displayIdentifier)"
    }

    private static func builtInDisplayIdentifier(for screen: NSScreen) -> String? {
        guard
            let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else {
            return nil
        }

        let displayID = CGDirectDisplayID(truncating: screenNumber)
        guard CGDisplayIsBuiltin(displayID) != 0 else {
            return nil
        }

        return String(displayID)
    }
}
