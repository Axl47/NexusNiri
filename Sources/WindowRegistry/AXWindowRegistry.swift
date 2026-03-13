import AppKit
import ApplicationServices
import Foundation
import SharedTypes

public actor AXWindowRegistry: WindowRegistryService, WindowControlling {
    public init() {}

    public func snapshot() async throws -> WindowRegistrySnapshot {
        let accessibilityTrusted = AXIsProcessTrusted()
        var notes: [String] = []
        var windows = quartzWindows()

        if accessibilityTrusted {
            let axWindows = accessibilityWindows()
            if !axWindows.isEmpty {
                windows = merge(quartzWindows: windows, accessibilityWindows: axWindows)
                notes.append("Accessibility metadata merged into Quartz window discovery.")
            } else {
                notes.append("Accessibility is granted, but no AX windows were discovered.")
            }
        } else {
            notes.append("Accessibility is not granted. Falling back to Quartz window metadata only.")
        }

        return WindowRegistrySnapshot(
            generatedAt: .now,
            isAccessibilityTrusted: accessibilityTrusted,
            notes: notes,
            windows: windows.sorted { lhs, rhs in
                if lhs.appName == rhs.appName {
                    return lhs.windowTitle < rhs.windowTitle
                }
                return lhs.appName < rhs.appName
            }
        )
    }

    public func setWindowFrame(processID: Int, windowID: Int?, to frame: RectValue) async throws {
        let windowElement = try matchingWindowElement(processID: processID, windowID: windowID)

        try setAttributeValue(
            positionValue(for: CGPoint(x: frame.x, y: frame.y)),
            for: windowElement,
            attribute: kAXPositionAttribute as CFString
        )
        try setAttributeValue(
            sizeValue(for: CGSize(width: frame.width, height: frame.height)),
            for: windowElement,
            attribute: kAXSizeAttribute as CFString
        )
    }

    public func setWindowMinimized(processID: Int, windowID: Int?, to minimized: Bool) async throws {
        let windowElement = try matchingWindowElement(processID: processID, windowID: windowID)
        try setAttributeValue(
            minimized ? kCFBooleanTrue : kCFBooleanFalse,
            for: windowElement,
            attribute: kAXMinimizedAttribute as CFString
        )
    }

    public func setApplicationHidden(processID: Int, to hidden: Bool) async throws {
        guard let application = NSRunningApplication(processIdentifier: pid_t(processID)) else {
            throw NexusError.notFound("No running application found for process \(processID).")
        }

        if hidden {
            application.hide()
        } else {
            application.unhide()
        }
    }

    public func activateApplication(processID: Int) async throws {
        guard let application = NSRunningApplication(processIdentifier: pid_t(processID)) else {
            throw NexusError.notFound("No running application found for process \(processID).")
        }

        application.activate(options: [.activateAllWindows])
    }

    public func raiseWindow(processID: Int, windowID: Int?) async throws {
        let windowElement = try matchingWindowElement(processID: processID, windowID: windowID)
        let error = AXUIElementPerformAction(windowElement, kAXRaiseAction as CFString)
        guard error == .success else {
            throw NexusError.invalidState("Unable to raise window \(windowID.map(String.init) ?? "unknown") for process \(processID): \(error.rawValue)")
        }
    }

    public func focusWindow(processID: Int, windowID: Int?) async throws {
        try await activateApplication(processID: processID)

        let windowElement = try matchingWindowElement(processID: processID, windowID: windowID)

        do {
            try setAttributeValue(kCFBooleanTrue, for: windowElement, attribute: kAXMainAttribute as CFString)
        } catch {
            // Some apps reject AXMainAttribute writes; raising is still a useful fallback.
        }

        do {
            try setAttributeValue(kCFBooleanTrue, for: windowElement, attribute: kAXFocusedAttribute as CFString)
        } catch {
            // Some windows do not expose focus writes even when they support raise.
        }

        try await raiseWindow(processID: processID, windowID: windowID)
    }

    private func quartzWindows() -> [WindowCandidate] {
        guard let rawList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return rawList.compactMap { entry in
            guard let ownerName = entry[kCGWindowOwnerName as String] as? String,
                  let ownerPID = entry[kCGWindowOwnerPID as String] as? Int else {
                return nil
            }

            let windowID = entry[kCGWindowNumber as String] as? Int
            let title = (entry[kCGWindowName as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let bounds = entry[kCGWindowBounds as String] as? [String: Any]
            let frame = rectValue(from: bounds)
            let app = NSRunningApplication(processIdentifier: pid_t(ownerPID))

            return WindowCandidate(
                bundleID: app?.bundleIdentifier,
                appName: ownerName,
                windowTitle: title?.isEmpty == false ? title! : ownerName,
                processID: ownerPID,
                windowID: windowID,
                frame: frame,
                displayID: displayID(for: frame),
                isFocused: false,
                isMinimized: false,
                source: .quartz
            )
        }
    }

    private func accessibilityWindows() -> [WindowCandidate] {
        var candidates: [WindowCandidate] = []

        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier else { continue }
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            let focusedWindow = focusedWindowElement(for: appElement)
            let windows = windowElements(for: appElement)

            let appCandidates = windows.map { windowElement -> WindowCandidate in
                let title = stringValue(for: windowElement, attribute: kAXTitleAttribute as CFString) ?? app.localizedName ?? bundleID
                let position = pointValue(for: windowElement, attribute: kAXPositionAttribute as CFString)
                let size = sizeValue(for: windowElement, attribute: kAXSizeAttribute as CFString)
                let minimized = boolValue(for: windowElement, attribute: kAXMinimizedAttribute as CFString) ?? false
                let windowID = intValue(for: windowElement, attribute: "AXWindowNumber" as CFString)
                let frame = RectValue(
                    x: Double(position?.x ?? 0),
                    y: Double(position?.y ?? 0),
                    width: Double(size?.width ?? 0),
                    height: Double(size?.height ?? 0)
                )

                return WindowCandidate(
                    id: "\(bundleID)-\(windowID ?? Int.random(in: 1...999_999))",
                    bundleID: bundleID,
                    appName: app.localizedName ?? bundleID,
                    windowTitle: title,
                    processID: Int(app.processIdentifier),
                    windowID: windowID,
                    frame: frame,
                    displayID: displayID(for: frame),
                    isFocused: focusedWindow.map { CFEqual($0, windowElement) } ?? false,
                    isMinimized: minimized,
                    source: .accessibility
                )
            }

            candidates.append(contentsOf: appCandidates)
        }

        return candidates
    }

    private func matchingWindowElement(processID: Int, windowID: Int?) throws -> AXUIElement {
        guard let application = NSRunningApplication(processIdentifier: pid_t(processID)) else {
            throw NexusError.notFound("No running application found for process \(processID).")
        }

        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        let windows = windowElements(for: appElement)

        if let windowID,
           let exactMatch = windows.first(where: { intValue(for: $0, attribute: "AXWindowNumber" as CFString) == windowID }) {
            return exactMatch
        }

        if let focusedWindow = focusedWindowElement(for: appElement),
           windows.contains(where: { CFEqual($0, focusedWindow) }) {
            return focusedWindow
        }

        if let mainStandardWindow = windows.first(where: { isPrimaryStandardWindow($0) }) {
            return mainStandardWindow
        }

        if let standardWindow = preferredStandardWindow(from: windows) {
            return standardWindow
        }

        if windows.count == 1, let firstWindow = windows.first {
            return firstWindow
        }

        if let firstWindow = windows.first {
            return firstWindow
        }

        throw NexusError.notFound("No accessibility window found for process \(processID).")
    }

    private func merge(quartzWindows: [WindowCandidate], accessibilityWindows: [WindowCandidate]) -> [WindowCandidate] {
        var merged = quartzWindows

        for axWindow in accessibilityWindows {
            if let index = merged.firstIndex(where: { candidate in
                candidate.processID == axWindow.processID &&
                candidate.windowTitle == axWindow.windowTitle
            }) {
                merged[index] = axWindow
            } else {
                merged.append(axWindow)
            }
        }

        return merged
    }

    private func windowElements(for applicationElement: AXUIElement) -> [AXUIElement] {
        guard let value = copyAttributeValue(for: applicationElement, attribute: kAXWindowsAttribute as CFString) else {
            return []
        }
        return value as? [AXUIElement] ?? []
    }

    private func focusedWindowElement(for applicationElement: AXUIElement) -> AXUIElement? {
        guard let focusedWindow = copyAttributeValue(for: applicationElement, attribute: kAXFocusedWindowAttribute as CFString),
              CFGetTypeID(focusedWindow) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(focusedWindow, to: AXUIElement.self)
    }

    private func isPrimaryStandardWindow(_ element: AXUIElement) -> Bool {
        stringValue(for: element, attribute: kAXRoleAttribute as CFString) == (kAXWindowRole as String) &&
        stringValue(for: element, attribute: kAXSubroleAttribute as CFString) == (kAXStandardWindowSubrole as String) &&
        boolValue(for: element, attribute: kAXMainAttribute as CFString) == true &&
        boolValue(for: element, attribute: kAXMinimizedAttribute as CFString) != true
    }

    private func preferredStandardWindow(from windows: [AXUIElement]) -> AXUIElement? {
        let candidates = windows
            .filter { boolValue(for: $0, attribute: kAXMinimizedAttribute as CFString) != true }
            .sorted { lhs, rhs in
                preferredWindowScore(lhs) > preferredWindowScore(rhs)
            }

        return candidates.first
    }

    private func preferredWindowScore(_ element: AXUIElement) -> Double {
        let role = stringValue(for: element, attribute: kAXRoleAttribute as CFString)
        let subrole = stringValue(for: element, attribute: kAXSubroleAttribute as CFString)
        let size = sizeValue(for: element, attribute: kAXSizeAttribute as CFString) ?? .zero
        let area = size.width * size.height

        var score = area
        if role == (kAXWindowRole as String) {
            score += 10_000
        }
        if subrole == (kAXStandardWindowSubrole as String) {
            score += 20_000
        }
        if boolValue(for: element, attribute: kAXMainAttribute as CFString) == true {
            score += 30_000
        }
        return score
    }

    private func copyAttributeValue(for element: AXUIElement, attribute: CFString) -> CFTypeRef? {
        var result: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &result)
        guard error == .success else { return nil }
        return result
    }

    private func stringValue(for element: AXUIElement, attribute: CFString) -> String? {
        copyAttributeValue(for: element, attribute: attribute) as? String
    }

    private func boolValue(for element: AXUIElement, attribute: CFString) -> Bool? {
        copyAttributeValue(for: element, attribute: attribute) as? Bool
    }

    private func intValue(for element: AXUIElement, attribute: CFString) -> Int? {
        guard let number = copyAttributeValue(for: element, attribute: attribute) as? NSNumber else {
            return nil
        }
        return number.intValue
    }

    private func pointValue(for element: AXUIElement, attribute: CFString) -> CGPoint? {
        guard let value = copyAttributeValue(for: element, attribute: attribute) else { return nil }
        return axValue(value, as: CGPoint.self, type: .cgPoint)
    }

    private func sizeValue(for element: AXUIElement, attribute: CFString) -> CGSize? {
        guard let value = copyAttributeValue(for: element, attribute: attribute) else { return nil }
        return axValue(value, as: CGSize.self, type: .cgSize)
    }

    private func axValue<T>(_ value: CFTypeRef, as type: T.Type, type axType: AXValueType) -> T? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == axType else { return nil }

        var result = makeDefaultValue(type)
        let success = withUnsafeMutablePointer(to: &result) { pointer in
            AXValueGetValue(axValue, axType, pointer)
        }
        return success ? result : nil
    }

    private func makeDefaultValue<T>(_ type: T.Type) -> T {
        switch type {
        case is CGPoint.Type:
            return CGPoint.zero as! T
        case is CGSize.Type:
            return CGSize.zero as! T
        default:
            fatalError("Unsupported AXValue type \(type)")
        }
    }

    private func setAttributeValue(_ value: CFTypeRef, for element: AXUIElement, attribute: CFString) throws {
        let error = AXUIElementSetAttributeValue(element, attribute, value)
        guard error == .success else {
            throw NexusError.invalidState("Unable to set AX attribute \(attribute) for window: \(error.rawValue)")
        }
    }

    private func positionValue(for point: CGPoint) throws -> AXValue {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else {
            throw NexusError.invalidState("Unable to encode AX position value.")
        }
        return value
    }

    private func sizeValue(for size: CGSize) throws -> AXValue {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else {
            throw NexusError.invalidState("Unable to encode AX size value.")
        }
        return value
    }

    private func rectValue(from dictionary: [String: Any]?) -> RectValue {
        guard let dictionary else { return .zero }
        return RectValue(
            x: dictionary["X"] as? Double ?? 0,
            y: dictionary["Y"] as? Double ?? 0,
            width: dictionary["Width"] as? Double ?? 0,
            height: dictionary["Height"] as? Double ?? 0
        )
    }

    private func displayID(for frame: RectValue) -> String? {
        let point = NSPoint(x: frame.midX, y: frame.y + (frame.height / 2))
        let screen = NSScreen.screens.first { $0.frame.contains(point) }
        return screen?.localizedName
    }
}
