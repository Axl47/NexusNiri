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
    private var savedWindowedStateCaptured = false

    func attach(window: NSWindow?) {
        self.window = window

        guard let window else {
            currentDisplayLayout = nil
            savedWindowedFrame = nil
            savedWindowedStyleMask = nil
            savedWindowedCollectionBehavior = nil
            savedWindowedIsMovable = nil
            savedWindowedStateCaptured = false
            return
        }

        if currentMode == .windowed {
            captureWindowedStateIfNeeded(from: window)
            currentDisplayLayout = makeWindowedLayout(for: window)
        }
    }

    func apply(mode: ShellPresentationMode, screen: NSScreen?) {
        guard let window else {
            currentDisplayLayout = nil
            return
        }

        let resolvedScreen = screen ?? window.screen ?? NSScreen.main

        switch mode {
        case .windowed:
            if currentMode != .windowed {
                restoreWindowedState(on: window)
            }
            currentDisplayLayout = makeWindowedLayout(for: window)
        case .notchFill:
            captureWindowedStateIfNeeded(from: window)
            if shouldApplyNotchFill(to: window, screen: resolvedScreen) {
                applyNotchFill(to: window, screen: resolvedScreen)
            }
            currentDisplayLayout = resolvedScreen.map(makeNotchFillLayout(for:))
        }

        currentMode = mode
    }

    func currentLayout() -> ShellDisplayLayout? {
        currentDisplayLayout
    }

    private func captureWindowedStateIfNeeded(from window: NSWindow) {
        guard savedWindowedStateCaptured == false else { return }
        savedWindowedFrame = window.frame
        savedWindowedStyleMask = window.styleMask
        savedWindowedCollectionBehavior = window.collectionBehavior
        savedWindowedIsMovable = window.isMovable
        savedWindowedStateCaptured = true
    }

    private func restoreWindowedState(on window: NSWindow) {
        if let savedWindowedStyleMask {
            if window.styleMask != savedWindowedStyleMask {
                window.styleMask = savedWindowedStyleMask
            }
        }
        if let savedWindowedCollectionBehavior {
            if window.collectionBehavior != savedWindowedCollectionBehavior {
                window.collectionBehavior = savedWindowedCollectionBehavior
            }
        }
        if let savedWindowedIsMovable {
            if window.isMovable != savedWindowedIsMovable {
                window.isMovable = savedWindowedIsMovable
            }
        }
        if let savedWindowedFrame, window.frame.integral != savedWindowedFrame.integral {
            window.setFrame(savedWindowedFrame, display: true)
        }

        if NSApp.presentationOptions != [] {
            NSApp.presentationOptions = []
        }
        savedWindowedStateCaptured = false
    }

    private func applyNotchFill(to window: NSWindow, screen: NSScreen?) {
        guard let screen else {
            currentDisplayLayout = makeWindowedLayout(for: window)
            return
        }

        let targetPresentationOptions: NSApplication.PresentationOptions = [.autoHideDock, .autoHideMenuBar]
        if NSApp.presentationOptions != targetPresentationOptions {
            NSApp.presentationOptions = targetPresentationOptions
        }
        let targetCollectionBehavior: NSWindow.CollectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        if window.collectionBehavior != targetCollectionBehavior {
            window.collectionBehavior = targetCollectionBehavior
        }
        let targetStyleMask: NSWindow.StyleMask = [.borderless]
        if window.styleMask != targetStyleMask {
            window.styleMask = targetStyleMask
        }
        if window.isMovable {
            window.isMovable = false
        }

        let targetFrame = screen.frame.integral
        if window.frame.integral != targetFrame {
            window.setFrame(targetFrame, display: true)
        }
    }

    private func shouldApplyNotchFill(to window: NSWindow, screen: NSScreen?) -> Bool {
        guard let screen else { return false }

        let targetPresentationOptions: NSApplication.PresentationOptions = [.autoHideDock, .autoHideMenuBar]
        let targetCollectionBehavior: NSWindow.CollectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        let targetStyleMask: NSWindow.StyleMask = [.borderless]
        let targetFrame = screen.frame.integral

        if currentMode != .notchFill {
            return true
        }
        if NSApp.presentationOptions != targetPresentationOptions {
            return true
        }
        if window.collectionBehavior != targetCollectionBehavior {
            return true
        }
        if window.styleMask != targetStyleMask {
            return true
        }
        if window.isMovable {
            return true
        }

        return window.frame.integral != targetFrame
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
