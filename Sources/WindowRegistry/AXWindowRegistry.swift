import AppKit
import ApplicationServices
import Foundation
import OSLog
import SharedTypes

public actor AXWindowRegistry: WindowRegistryService, WindowControlling {
    private let focusLogger = Logger(subsystem: "dev.nexusniri.Nexus", category: "focusSync")
    private let focusedWindowAttribution = FocusedWindowAttribution()
    private var lastLoggedFocusedWindowResolution: FocusedWindowAttribution.Resolution?

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

    public func focusedWindowCandidate() async throws -> WindowCandidate? {
        guard AXIsProcessTrusted() else { return nil }

        let systemWideElement = AXUIElementCreateSystemWide()
        let focusedApplication = focusedApplication(for: systemWideElement)
        let frontmostApplication = NSWorkspace.shared.frontmostApplication

        let focusedWindowLookup = focusedWindowCandidate(
            from: systemWideElement,
            focusedApplication: focusedApplication,
            frontmostApplication: frontmostApplication
        )
        if let candidate = focusedWindowLookup.candidate {
            return candidate
        }
        if focusedWindowLookup.shouldContinue == false {
            return nil
        }

        guard let focusedApplication else {
            return fallbackFocusedWindowCandidate(frontmostApplication: frontmostApplication)
        }

        let applicationElement = AXUIElementCreateApplication(focusedApplication.processIdentifier)
        let focusedWindow = focusedWindowElement(for: applicationElement)
            ?? mainWindowElement(for: applicationElement)
            ?? preferredStandardWindow(from: windowElements(for: applicationElement))

        guard let focusedWindow else {
            return fallbackFocusedWindowCandidate(frontmostApplication: frontmostApplication)
        }

        return candidate(
            for: focusedWindow,
            in: focusedApplication,
            bundleID: focusedApplication.bundleIdentifier,
            isFocused: true
        )
    }

    private func focusedWindowCandidate(
        from systemWideElement: AXUIElement,
        focusedApplication: NSRunningApplication?,
        frontmostApplication: NSRunningApplication?
    ) -> (candidate: WindowCandidate?, shouldContinue: Bool) {
        let focusedUIElement = focusedUIElement(for: systemWideElement)
        let focusedWindow = focusedUIElement.flatMap { containingWindowElement(for: $0) ?? focusedUIElementCandidateWindow(from: $0) }
        let focusedElementProcessID = focusedUIElement.flatMap(processID(for:))
        let focusedWindowProcessID = focusedWindow.flatMap(processID(for:))
        let focusedWindowRole = focusedWindow.flatMap { stringValue(for: $0, attribute: kAXRoleAttribute as CFString) }
        let focusedWindowSubrole = focusedWindow.flatMap { stringValue(for: $0, attribute: kAXSubroleAttribute as CFString) }
        let frontmostHostWindow = frontmostApplication.flatMap(standardHostWindowElement(for:))

        let resolution = focusedWindowAttribution.resolve(
            FocusedWindowAttribution.Context(
                focusedElementProcessID: focusedElementProcessID,
                focusedWindowProcessID: focusedWindowProcessID,
                focusedApplicationProcessID: focusedApplication.map { Int($0.processIdentifier) },
                focusedApplicationBundleID: focusedApplication?.bundleIdentifier,
                focusedWindowRole: focusedWindowRole,
                focusedWindowSubrole: focusedWindowSubrole,
                frontmostApplicationProcessID: frontmostApplication.map { Int($0.processIdentifier) },
                frontmostApplicationBundleID: frontmostApplication?.bundleIdentifier,
                hostStandardWindowAvailable: frontmostHostWindow != nil
            ),
            nexusProcessID: Int(ProcessInfo.processInfo.processIdentifier),
            nexusBundleID: Bundle.main.bundleIdentifier
        )
        logFocusedWindowResolution(resolution)

        switch resolution.decision {
        case .useFocusedOwner:
            guard let focusedWindow,
                  let application = application(for: resolution.resolvedOwnerProcessID) else {
                return (nil, true)
            }

            return (candidate(
                for: focusedWindow,
                in: application,
                bundleID: application.bundleIdentifier ?? resolution.resolvedOwnerBundleID,
                isFocused: true
            ), false)
        case .useFrontmostHost:
            guard let frontmostApplication,
                  let frontmostHostWindow else {
                return (nil, false)
            }

            return (candidate(
                for: frontmostHostWindow,
                in: frontmostApplication,
                bundleID: frontmostApplication.bundleIdentifier,
                isFocused: true
            ), false)
        case .ignoreFrontmostNexus, .ignoreMissingHostWindow:
            return (nil, false)
        case .unresolved:
            return (nil, true)
        }
    }

    private func fallbackFocusedWindowCandidate(frontmostApplication: NSRunningApplication?) -> WindowCandidate? {
        if let frontmostApplication {
            let applicationElement = AXUIElementCreateApplication(frontmostApplication.processIdentifier)
            let frontmostWindow = focusedWindowElement(for: applicationElement)
                ?? mainWindowElement(for: applicationElement)
                ?? preferredStandardWindow(from: windowElements(for: applicationElement))

            if let frontmostWindow {
                return candidate(
                    for: frontmostWindow,
                    in: frontmostApplication,
                    bundleID: frontmostApplication.bundleIdentifier,
                    isFocused: true
                )
            }

            let appWindows = accessibilityWindows().filter {
                $0.processID == Int(frontmostApplication.processIdentifier)
            }

            if let focused = appWindows.first(where: { $0.isFocused }) {
                return focused
            }

            if let visible = appWindows.first(where: { $0.isMinimized == false }) {
                return visible
            }
        }

        let axWindows = accessibilityWindows()
        if let focused = axWindows.first(where: { $0.isFocused }) {
            return focused
        }

        return nil
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

        application.activate(options: [])
    }

    public func raiseWindow(processID: Int, windowID: Int?) async throws {
        let windowElement = try matchingWindowElement(processID: processID, windowID: windowID)
        let error = AXUIElementPerformAction(windowElement, kAXRaiseAction as CFString)
        guard error == .success else {
            throw NexusError.invalidState("Unable to raise window \(windowID.map(String.init) ?? "unknown") for process \(processID): \(error.rawValue)")
        }
    }

    public func focusWindow(processID: Int, windowID: Int?) async throws {
        let windowElement = try matchingWindowElement(processID: processID, windowID: windowID)

        do {
            try setAttributeValue(kCFBooleanTrue, for: windowElement, attribute: kAXMainAttribute as CFString)
        } catch {
            // Some apps reject AXMainAttribute writes.
        }

        do {
            try setAttributeValue(kCFBooleanTrue, for: windowElement, attribute: kAXFocusedAttribute as CFString)
        } catch {
            // Some windows do not expose focus writes even when they support raise.
        }

        try await activateApplication(processID: processID)
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
            let bundleID = app.bundleIdentifier
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            let focusedWindow = focusedWindowElement(for: appElement)
            let windows = windowElements(for: appElement)

            let appCandidates = windows.compactMap { windowElement -> WindowCandidate? in
                candidate(
                    for: windowElement,
                    in: app,
                    bundleID: bundleID,
                    isFocused: focusedWindow.map { CFEqual($0, windowElement) } ?? false
                )
            }

            candidates.append(contentsOf: appCandidates)
        }

        return candidates
    }

    private func candidate(
        for windowElement: AXUIElement,
        in application: NSRunningApplication,
        bundleID: String?,
        isFocused: Bool
    ) -> WindowCandidate {
        let title = stringValue(for: windowElement, attribute: kAXTitleAttribute as CFString)
            ?? application.localizedName
            ?? bundleID
            ?? "Process \(application.processIdentifier)"
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
            id: [
                bundleID ?? "pid-\(application.processIdentifier)",
                String(windowID ?? 0),
                title
            ].joined(separator: "::"),
            bundleID: bundleID,
            appName: application.localizedName ?? bundleID ?? "Process \(application.processIdentifier)",
            windowTitle: title,
            processID: Int(application.processIdentifier),
            windowID: windowID,
            frame: frame,
            displayID: displayID(for: frame),
            isFocused: isFocused,
            isMinimized: minimized,
            source: .accessibility
        )
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

    private func focusedApplication(for systemWideElement: AXUIElement) -> NSRunningApplication? {
        guard let focusedApplicationValue = copyAttributeValue(
            for: systemWideElement,
            attribute: kAXFocusedApplicationAttribute as CFString
        ),
        CFGetTypeID(focusedApplicationValue) == AXUIElementGetTypeID() else {
            return nil
        }

        let applicationElement = unsafeDowncast(focusedApplicationValue, to: AXUIElement.self)
        guard let processIdentifier = processID(for: applicationElement) else {
            return nil
        }

        return application(for: processIdentifier)
    }

    private func focusedWindowElement(for applicationElement: AXUIElement) -> AXUIElement? {
        guard let focusedWindow = copyAttributeValue(for: applicationElement, attribute: kAXFocusedWindowAttribute as CFString),
              CFGetTypeID(focusedWindow) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(focusedWindow, to: AXUIElement.self)
    }

    private func focusedUIElement(for systemWideElement: AXUIElement) -> AXUIElement? {
        guard let focusedElement = copyAttributeValue(
            for: systemWideElement,
            attribute: kAXFocusedUIElementAttribute as CFString
        ),
        CFGetTypeID(focusedElement) == AXUIElementGetTypeID() else {
            return nil
        }

        return unsafeDowncast(focusedElement, to: AXUIElement.self)
    }

    private func mainWindowElement(for applicationElement: AXUIElement) -> AXUIElement? {
        guard let mainWindow = copyAttributeValue(for: applicationElement, attribute: kAXMainWindowAttribute as CFString),
              CFGetTypeID(mainWindow) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(mainWindow, to: AXUIElement.self)
    }

    private func isPrimaryStandardWindow(_ element: AXUIElement) -> Bool {
        stringValue(for: element, attribute: kAXRoleAttribute as CFString) == (kAXWindowRole as String) &&
        stringValue(for: element, attribute: kAXSubroleAttribute as CFString) == (kAXStandardWindowSubrole as String) &&
        boolValue(for: element, attribute: kAXMainAttribute as CFString) == true &&
        boolValue(for: element, attribute: kAXMinimizedAttribute as CFString) != true
    }

    private func containingWindowElement(for element: AXUIElement) -> AXUIElement? {
        var currentElement: AXUIElement? = element
        var visited = Set<CFHashCode>()

        while let currentElementValue = currentElement {
            let identifier = CFHash(currentElementValue)
            guard visited.insert(identifier).inserted else {
                return nil
            }

            if isWindowLikeElement(currentElementValue) {
                return currentElementValue
            }

            guard let parent = parentElement(for: currentElementValue) else {
                return nil
            }

            currentElement = parent
        }

        return nil
    }

    private func focusedUIElementCandidateWindow(from element: AXUIElement) -> AXUIElement? {
        guard isWindowLikeElement(element) else {
            return nil
        }
        return element
    }

    private func parentElement(for element: AXUIElement) -> AXUIElement? {
        guard let parent = copyAttributeValue(for: element, attribute: kAXParentAttribute as CFString),
              CFGetTypeID(parent) == AXUIElementGetTypeID() else {
            return nil
        }

        return unsafeDowncast(parent, to: AXUIElement.self)
    }

    private func isWindowLikeElement(_ element: AXUIElement) -> Bool {
        guard let role = stringValue(for: element, attribute: kAXRoleAttribute as CFString) else {
            return false
        }

        switch role {
        case String(kAXWindowRole), String(kAXSheetRole):
            return true
        default:
            return false
        }
    }

    private func standardHostWindowElement(for application: NSRunningApplication) -> AXUIElement? {
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        let windows = windowElements(for: applicationElement)

        if let focusedWindow = focusedWindowElement(for: applicationElement),
           isStandardHostWindow(focusedWindow) {
            return focusedWindow
        }

        if let mainWindow = mainWindowElement(for: applicationElement),
           isStandardHostWindow(mainWindow) {
            return mainWindow
        }

        if let primaryStandardWindow = windows.first(where: isPrimaryStandardWindow) {
            return primaryStandardWindow
        }

        let standardWindows = windows.filter(isStandardHostWindow).sorted { lhs, rhs in
            preferredWindowScore(lhs) > preferredWindowScore(rhs)
        }
        return standardWindows.first
    }

    private func isStandardHostWindow(_ element: AXUIElement) -> Bool {
        guard boolValue(for: element, attribute: kAXMinimizedAttribute as CFString) != true,
              stringValue(for: element, attribute: kAXRoleAttribute as CFString) == String(kAXWindowRole) else {
            return false
        }

        guard let subrole = stringValue(for: element, attribute: kAXSubroleAttribute as CFString) else {
            return true
        }

        return subrole == String(kAXStandardWindowSubrole)
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

    private func processID(for element: AXUIElement) -> Int? {
        var processIdentifier: pid_t = 0
        let error = AXUIElementGetPid(element, &processIdentifier)
        guard error == .success else {
            return nil
        }
        return Int(processIdentifier)
    }

    private func application(for processID: Int?) -> NSRunningApplication? {
        guard let processID else {
            return nil
        }
        return NSRunningApplication(processIdentifier: pid_t(processID))
    }

    private func logFocusedWindowResolution(_ resolution: FocusedWindowAttribution.Resolution) {
        guard resolution != lastLoggedFocusedWindowResolution else {
            return
        }

        lastLoggedFocusedWindowResolution = resolution
        focusLogger.debug(
            """
            Focus attribution decision=\(String(describing: resolution.decision), privacy: .public) \
            helperToHost=\(resolution.helperToHostAttributionUsed, privacy: .public) \
            focusedElementPID=\(String(describing: resolution.focusedElementProcessID), privacy: .public) \
            focusedWindowPID=\(String(describing: resolution.focusedWindowProcessID), privacy: .public) \
            focusedAppPID=\(String(describing: resolution.focusedApplicationProcessID), privacy: .public) \
            focusedAppBundle=\(resolution.focusedApplicationBundleID ?? "nil", privacy: .public) \
            frontmostPID=\(String(describing: resolution.frontmostApplicationProcessID), privacy: .public) \
            frontmostBundle=\(resolution.frontmostApplicationBundleID ?? "nil", privacy: .public) \
            resolvedOwnerPID=\(String(describing: resolution.resolvedOwnerProcessID), privacy: .public) \
            resolvedOwnerBundle=\(resolution.resolvedOwnerBundleID ?? "nil", privacy: .public) \
            role=\(resolution.focusedWindowRole ?? "nil", privacy: .public) \
            subrole=\(resolution.focusedWindowSubrole ?? "nil", privacy: .public)
            """
        )
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
