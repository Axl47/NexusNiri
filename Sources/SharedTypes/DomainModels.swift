import CoreGraphics
import Foundation

public enum DisplayPolicy: String, Codable, Sendable, CaseIterable {
    case staticAssignment = "static"
    case dynamic
}

public enum SlotKind: String, Codable, Sendable, CaseIterable {
    case single
    case stacked
    case ownedSurface
    case externalWindow
    case hybrid
}

public enum LayoutRole: String, Codable, Sendable, CaseIterable {
    case primary
    case secondary
    case support
    case floating
}

public enum WarmPreference: String, Codable, Sendable, CaseIterable {
    case hot
    case warm
    case cold
}

public enum WidthMode: String, Codable, Sendable, CaseIterable {
    case fraction
    case fixed
    case fullWidth
}

public enum HeightMode: String, Codable, Sendable, CaseIterable {
    case fill
    case fixed
}

public enum VisibilityStrategy: String, Codable, Sendable, CaseIterable {
    case inStage
    case edgeSliver
    case safeZone
    case appHide
    case windowMinimize
}

public enum RuntimeBindingState: String, Codable, Sendable, CaseIterable {
    case attached
    case detached
    case recovering
}

public enum AdapterHealth: String, Codable, Sendable, CaseIterable {
    case healthy
    case degraded
    case unavailable
    case recovering
    case disabled
}

public enum VisibilityMode: String, Codable, Sendable, CaseIterable {
    case visible
    case parked
    case hidden
    case minimized
    case detached
}

public enum VisibilityActionKind: String, Codable, Sendable, CaseIterable {
    case show
    case park
    case minimize
    case hideApp
    case detach
    case reveal
}

public enum SnapshotReason: String, Codable, Sendable, CaseIterable {
    case manual
    case deactivate
    case periodic
    case crashRecovery
}

public enum WindowDiscoverySource: String, Codable, Sendable, CaseIterable {
    case accessibility
    case quartz
    case synthetic
}

public enum PermissionState: String, Codable, Sendable, CaseIterable {
    case granted
    case denied
    case notDetermined
    case unsupported
    case unknown
}

public enum PermissionKind: String, Codable, Sendable, CaseIterable {
    case accessibility
    case automation
    case screenRecording
}

public enum BuildSigningMode: String, Codable, Sendable, CaseIterable {
    case selfSigned
    case adHoc
    case unknown
}

public enum HotkeyCommand: String, Codable, Sendable, CaseIterable {
    case nextSlot
    case previousSlot
    case nextWorkspace
    case previousWorkspace
    case toggleDiagnostics
    case revealAll
}

public struct SizePolicy: Codable, Equatable, Sendable {
    public var mode: WidthMode
    public var value: Double?
    public var minimum: Double?
    public var maximum: Double?

    public init(mode: WidthMode, value: Double? = nil, minimum: Double? = nil, maximum: Double? = nil) {
        self.mode = mode
        self.value = value
        self.minimum = minimum
        self.maximum = maximum
    }
}

public struct HeightPolicy: Codable, Equatable, Sendable {
    public var mode: HeightMode
    public var value: Double?
    public var minimum: Double?
    public var maximum: Double?

    public init(mode: HeightMode, value: Double? = nil, minimum: Double? = nil, maximum: Double? = nil) {
        self.mode = mode
        self.value = value
        self.minimum = minimum
        self.maximum = maximum
    }
}

public struct VisibilityPolicy: Codable, Equatable, Sendable {
    public var defaultStrategy: VisibilityStrategy
    public var prefersHideForBackgroundApps: Bool
    public var keepsFloatsVisible: Bool
    public var revealAllShortcutEnabled: Bool

    public init(
        defaultStrategy: VisibilityStrategy = .edgeSliver,
        prefersHideForBackgroundApps: Bool = false,
        keepsFloatsVisible: Bool = true,
        revealAllShortcutEnabled: Bool = true
    ) {
        self.defaultStrategy = defaultStrategy
        self.prefersHideForBackgroundApps = prefersHideForBackgroundApps
        self.keepsFloatsVisible = keepsFloatsVisible
        self.revealAllShortcutEnabled = revealAllShortcutEnabled
    }
}

public struct ResidencyPolicy: Codable, Equatable, Sendable {
    public var hotSlotIDs: [String]
    public var warmSlotIDs: [String]
    public var coldLaunchAllowed: Bool

    public init(hotSlotIDs: [String] = [], warmSlotIDs: [String] = [], coldLaunchAllowed: Bool = true) {
        self.hotSlotIDs = hotSlotIDs
        self.warmSlotIDs = warmSlotIDs
        self.coldLaunchAllowed = coldLaunchAllowed
    }
}

public struct LayoutState: Codable, Equatable, Sendable {
    public var activeIndex: Int
    public var scrollAnchor: Double
    public var centeredSlotID: String?
    public var visibleSlotIDs: [String]
    public var parkedSlotIDs: [String]
    public var geometryVersion: Int

    public init(
        activeIndex: Int = 0,
        scrollAnchor: Double = 0,
        centeredSlotID: String? = nil,
        visibleSlotIDs: [String] = [],
        parkedSlotIDs: [String] = [],
        geometryVersion: Int = 1
    ) {
        self.activeIndex = activeIndex
        self.scrollAnchor = scrollAnchor
        self.centeredSlotID = centeredSlotID
        self.visibleSlotIDs = visibleSlotIDs
        self.parkedSlotIDs = parkedSlotIDs
        self.geometryVersion = geometryVersion
    }
}

public struct RectValue: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let zero = RectValue(x: 0, y: 0, width: 0, height: 0)

    public var midX: Double { x + (width / 2) }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
}

public struct AppBinding: Codable, Equatable, Sendable {
    public var bundleID: String
    public var preferredProcessStrategy: String
    public var titleHints: [String]
    public var urlHints: [String]
    public var documentHints: [String]
    public var profileHint: String?
    public var launchCommand: String?
    public var adapterHints: [String: String]

    public init(
        bundleID: String,
        preferredProcessStrategy: String = "reuse",
        titleHints: [String] = [],
        urlHints: [String] = [],
        documentHints: [String] = [],
        profileHint: String? = nil,
        launchCommand: String? = nil,
        adapterHints: [String: String] = [:]
    ) {
        self.bundleID = bundleID
        self.preferredProcessStrategy = preferredProcessStrategy
        self.titleHints = titleHints
        self.urlHints = urlHints
        self.documentHints = documentHints
        self.profileHint = profileHint
        self.launchCommand = launchCommand
        self.adapterHints = adapterHints
    }
}

public struct RuntimeBinding: Codable, Equatable, Sendable {
    public var processID: Int?
    public var windowID: Int?
    public var axPath: [String]
    public var matchConfidence: Double
    public var state: RuntimeBindingState
    public var lastSeenAt: Date?

    public init(
        processID: Int? = nil,
        windowID: Int? = nil,
        axPath: [String] = [],
        matchConfidence: Double = 0,
        state: RuntimeBindingState = .detached,
        lastSeenAt: Date? = nil
    ) {
        self.processID = processID
        self.windowID = windowID
        self.axPath = axPath
        self.matchConfidence = matchConfidence
        self.state = state
        self.lastSeenAt = lastSeenAt
    }
}

public struct Slot: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var workspaceID: String
    public var kind: SlotKind
    public var label: String
    public var appBinding: AppBinding?
    public var widthPolicy: SizePolicy
    public var heightPolicy: HeightPolicy
    public var layoutRole: LayoutRole
    public var adapterID: String?
    public var adapterStateID: String?
    public var runtimeBinding: RuntimeBinding?
    public var lastKnownDisplayID: String?
    public var pinned: Bool
    public var warmPreference: WarmPreference
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        workspaceID: String,
        kind: SlotKind,
        label: String,
        appBinding: AppBinding? = nil,
        widthPolicy: SizePolicy,
        heightPolicy: HeightPolicy = HeightPolicy(mode: .fill),
        layoutRole: LayoutRole,
        adapterID: String? = nil,
        adapterStateID: String? = nil,
        runtimeBinding: RuntimeBinding? = nil,
        lastKnownDisplayID: String? = nil,
        pinned: Bool = false,
        warmPreference: WarmPreference = .warm,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.kind = kind
        self.label = label
        self.appBinding = appBinding
        self.widthPolicy = widthPolicy
        self.heightPolicy = heightPolicy
        self.layoutRole = layoutRole
        self.adapterID = adapterID
        self.adapterStateID = adapterStateID
        self.runtimeBinding = runtimeBinding
        self.lastKnownDisplayID = lastKnownDisplayID
        self.pinned = pinned
        self.warmPreference = warmPreference
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct Workspace: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var description: String?
    public var profileID: String?
    public var displayPolicy: DisplayPolicy
    public var preferredDisplayID: String?
    public var activeSlotID: String?
    public var slotOrder: [String]
    public var floatingSlotIDs: [String]
    public var layoutState: LayoutState
    public var visibilityPolicy: VisibilityPolicy
    public var residencyPolicy: ResidencyPolicy
    public var assignmentRuleIDs: [String]
    public var adapterStateIDs: [String]
    public var snapshotIDs: [String]
    public var tags: [String]
    public var createdAt: Date
    public var updatedAt: Date
    public var slots: [Slot]

    public init(
        id: String = UUID().uuidString,
        name: String,
        description: String? = nil,
        profileID: String? = nil,
        displayPolicy: DisplayPolicy = .staticAssignment,
        preferredDisplayID: String? = nil,
        activeSlotID: String? = nil,
        slotOrder: [String] = [],
        floatingSlotIDs: [String] = [],
        layoutState: LayoutState = LayoutState(),
        visibilityPolicy: VisibilityPolicy = VisibilityPolicy(),
        residencyPolicy: ResidencyPolicy = ResidencyPolicy(),
        assignmentRuleIDs: [String] = [],
        adapterStateIDs: [String] = [],
        snapshotIDs: [String] = [],
        tags: [String] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now,
        slots: [Slot] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.profileID = profileID
        self.displayPolicy = displayPolicy
        self.preferredDisplayID = preferredDisplayID
        self.activeSlotID = activeSlotID
        self.slotOrder = slotOrder
        self.floatingSlotIDs = floatingSlotIDs
        self.layoutState = layoutState
        self.visibilityPolicy = visibilityPolicy
        self.residencyPolicy = residencyPolicy
        self.assignmentRuleIDs = assignmentRuleIDs
        self.adapterStateIDs = adapterStateIDs
        self.snapshotIDs = snapshotIDs
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.slots = slots
    }

    public var orderedSlots: [Slot] {
        let slotsByID = Dictionary(uniqueKeysWithValues: slots.map { ($0.id, $0) })
        let ordered = slotOrder.compactMap { slotsByID[$0] }
        let remaining = slots.filter { !slotOrder.contains($0.id) }
        return ordered + remaining
    }
}

public struct AssignmentRule: Codable, Equatable, Identifiable, Sendable {
    public struct Match: Codable, Equatable, Sendable {
        public var bundleID: String?
        public var titleRegex: String?
        public var documentRegex: String?
        public var urlRegex: String?
        public var adapterPredicate: String?

        public init(
            bundleID: String? = nil,
            titleRegex: String? = nil,
            documentRegex: String? = nil,
            urlRegex: String? = nil,
            adapterPredicate: String? = nil
        ) {
            self.bundleID = bundleID
            self.titleRegex = titleRegex
            self.documentRegex = documentRegex
            self.urlRegex = urlRegex
            self.adapterPredicate = adapterPredicate
        }
    }

    public struct Action: Codable, Equatable, Sendable {
        public var workspaceID: String?
        public var floating: Bool
        public var preferredDisplayID: String?
        public var preferredSlotID: String?

        public init(
            workspaceID: String? = nil,
            floating: Bool = false,
            preferredDisplayID: String? = nil,
            preferredSlotID: String? = nil
        ) {
            self.workspaceID = workspaceID
            self.floating = floating
            self.preferredDisplayID = preferredDisplayID
            self.preferredSlotID = preferredSlotID
        }
    }

    public var id: String
    public var name: String
    public var match: Match
    public var action: Action
    public var enabled: Bool

    public init(id: String = UUID().uuidString, name: String, match: Match, action: Action, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.match = match
        self.action = action
        self.enabled = enabled
    }
}

public struct AdapterState: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var adapterID: String
    public var slotID: String
    public var health: AdapterHealth
    public var payload: [String: String]
    public var capturedAt: Date

    public init(
        id: String = UUID().uuidString,
        adapterID: String,
        slotID: String,
        health: AdapterHealth,
        payload: [String: String] = [:],
        capturedAt: Date = .now
    ) {
        self.id = id
        self.adapterID = adapterID
        self.slotID = slotID
        self.health = health
        self.payload = payload
        self.capturedAt = capturedAt
    }
}

public struct VisibilityState: Codable, Equatable, Identifiable, Sendable {
    public var id: String { slotID }
    public var slotID: String
    public var mode: VisibilityMode
    public var strategy: VisibilityStrategy
    public var updatedAt: Date

    public init(slotID: String, mode: VisibilityMode, strategy: VisibilityStrategy, updatedAt: Date = .now) {
        self.slotID = slotID
        self.mode = mode
        self.strategy = strategy
        self.updatedAt = updatedAt
    }
}

public struct SessionSnapshot: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var workspaceID: String
    public var reason: SnapshotReason
    public var slotStates: [String: String]
    public var capturedAt: Date

    public init(
        id: String = UUID().uuidString,
        workspaceID: String,
        reason: SnapshotReason,
        slotStates: [String: String] = [:],
        capturedAt: Date = .now
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.reason = reason
        self.slotStates = slotStates
        self.capturedAt = capturedAt
    }
}

public struct StageGeometry: Codable, Equatable, Sendable {
    public var viewportWidth: Double
    public var viewportHeight: Double
    public var sidebarWidth: Double
    public var topbarHeight: Double
    public var slotHeaderHeight: Double
    public var stripIndicatorHeight: Double
    public var slotGap: Double
    public var edgePeekWidth: Double

    public init(
        viewportWidth: Double,
        viewportHeight: Double,
        sidebarWidth: Double = 52,
        topbarHeight: Double = 36,
        slotHeaderHeight: Double = 28,
        stripIndicatorHeight: Double = 6,
        slotGap: Double = 2,
        edgePeekWidth: Double = 16
    ) {
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
        self.sidebarWidth = sidebarWidth
        self.topbarHeight = topbarHeight
        self.slotHeaderHeight = slotHeaderHeight
        self.stripIndicatorHeight = stripIndicatorHeight
        self.slotGap = slotGap
        self.edgePeekWidth = edgePeekWidth
    }

    public var stageWidth: Double { max(viewportWidth - sidebarWidth, 320) }
    public var stageHeight: Double { max(viewportHeight - topbarHeight, 240) }
    public var stageContentHeight: Double { max(stageHeight - stripIndicatorHeight, 180) }
}

public enum ShellPresentationMode: String, Codable, Sendable, CaseIterable {
    case windowed
    case notchFill
}

public struct ShellDisplayLayout: Codable, Equatable, Sendable {
    public var windowFrame: CGRect
    public var safeContentFrame: CGRect
    public var topLeftAuxiliaryFrame: CGRect?
    public var topRightAuxiliaryFrame: CGRect?
    public var hasCameraHousing: Bool

    public init(
        windowFrame: CGRect,
        safeContentFrame: CGRect,
        topLeftAuxiliaryFrame: CGRect? = nil,
        topRightAuxiliaryFrame: CGRect? = nil,
        hasCameraHousing: Bool
    ) {
        self.windowFrame = windowFrame
        self.safeContentFrame = safeContentFrame
        self.topLeftAuxiliaryFrame = topLeftAuxiliaryFrame
        self.topRightAuxiliaryFrame = topRightAuxiliaryFrame
        self.hasCameraHousing = hasCameraHousing
    }

    public func localSafeContentFrame() -> CGRect {
        localFrame(for: safeContentFrame)
    }

    public func localTopLeftAuxiliaryFrame() -> CGRect? {
        guard let topLeftAuxiliaryFrame else { return nil }
        return localFrame(for: topLeftAuxiliaryFrame)
    }

    public func localTopRightAuxiliaryFrame() -> CGRect? {
        guard let topRightAuxiliaryFrame else { return nil }
        return localFrame(for: topRightAuxiliaryFrame)
    }

    private func localFrame(for frame: CGRect) -> CGRect {
        let localMinX = frame.minX - windowFrame.minX
        let localMaxY = frame.maxY - windowFrame.minY
        return CGRect(
            x: localMinX,
            y: windowFrame.height - localMaxY,
            width: frame.width,
            height: frame.height
        )
    }
}

public struct SlotLayout: Codable, Equatable, Identifiable, Sendable {
    public var id: String { slotID }
    public var slotID: String
    public var frame: RectValue
    public var isFocused: Bool

    public init(slotID: String, frame: RectValue, isFocused: Bool) {
        self.slotID = slotID
        self.frame = frame
        self.isFocused = isFocused
    }
}

public enum RevealedSlotFragmentKind: String, Codable, Sendable, CaseIterable {
    case active
    case leftPeek
    case rightPeek
}

public struct RevealedSlotFragment: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(slotID)-\(kind.rawValue)" }
    public var slotID: String
    public var kind: RevealedSlotFragmentKind
    public var frame: RectValue

    public init(slotID: String, kind: RevealedSlotFragmentKind, frame: RectValue) {
        self.slotID = slotID
        self.kind = kind
        self.frame = frame
    }
}

public struct LayoutPlan: Codable, Equatable, Sendable {
    public var slotLayouts: [SlotLayout]
    public var contentWidth: Double
    public var scrollOffset: Double
    public var leadingPadding: Double
    public var trailingPadding: Double
    public var visibleSlotIDs: [String]
    public var parkedSlotIDs: [String]
    public var activeSlotIndex: Int
    public var revealedFragments: [RevealedSlotFragment]
    public var occlusionBands: [RectValue]

    public init(
        slotLayouts: [SlotLayout],
        contentWidth: Double,
        scrollOffset: Double,
        leadingPadding: Double = 0,
        trailingPadding: Double = 0,
        visibleSlotIDs: [String],
        parkedSlotIDs: [String],
        activeSlotIndex: Int,
        revealedFragments: [RevealedSlotFragment] = [],
        occlusionBands: [RectValue] = []
    ) {
        self.slotLayouts = slotLayouts
        self.contentWidth = contentWidth
        self.scrollOffset = scrollOffset
        self.leadingPadding = leadingPadding
        self.trailingPadding = trailingPadding
        self.visibleSlotIDs = visibleSlotIDs
        self.parkedSlotIDs = parkedSlotIDs
        self.activeSlotIndex = activeSlotIndex
        self.revealedFragments = revealedFragments
        self.occlusionBands = occlusionBands
    }
}

public struct VisibilityAction: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(slotID)-\(kind.rawValue)" }
    public var slotID: String
    public var windowID: Int?
    public var kind: VisibilityActionKind
    public var targetFrame: RectValue?

    public init(slotID: String, windowID: Int?, kind: VisibilityActionKind, targetFrame: RectValue? = nil) {
        self.slotID = slotID
        self.windowID = windowID
        self.kind = kind
        self.targetFrame = targetFrame
    }
}

public struct PermissionStatus: Codable, Equatable, Identifiable, Sendable {
    public var id: String { kind.rawValue }
    public var kind: PermissionKind
    public var state: PermissionState
    public var detail: String
    public var settingsURL: String?

    public init(kind: PermissionKind, state: PermissionState, detail: String, settingsURL: String? = nil) {
        self.kind = kind
        self.state = state
        self.detail = detail
        self.settingsURL = settingsURL
    }
}

public struct BuildIdentityStatus: Codable, Equatable, Sendable {
    public var bundlePath: String
    public var bundleIdentifier: String
    public var signingMode: BuildSigningMode
    public var signingIdentityLabel: String?
    public var expectedInstallPath: String?
    public var launchedFromExpectedPath: Bool
    public var buildTimestamp: Date?

    public init(
        bundlePath: String = "",
        bundleIdentifier: String = "",
        signingMode: BuildSigningMode = .unknown,
        signingIdentityLabel: String? = nil,
        expectedInstallPath: String? = nil,
        launchedFromExpectedPath: Bool = false,
        buildTimestamp: Date? = nil
    ) {
        self.bundlePath = bundlePath
        self.bundleIdentifier = bundleIdentifier
        self.signingMode = signingMode
        self.signingIdentityLabel = signingIdentityLabel
        self.expectedInstallPath = expectedInstallPath
        self.launchedFromExpectedPath = launchedFromExpectedPath
        self.buildTimestamp = buildTimestamp
    }
}

public struct WindowCandidate: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var bundleID: String?
    public var appName: String
    public var windowTitle: String
    public var processID: Int
    public var windowID: Int?
    public var frame: RectValue
    public var displayID: String?
    public var isFocused: Bool
    public var isMinimized: Bool
    public var source: WindowDiscoverySource

    public init(
        id: String = UUID().uuidString,
        bundleID: String? = nil,
        appName: String,
        windowTitle: String,
        processID: Int,
        windowID: Int? = nil,
        frame: RectValue,
        displayID: String? = nil,
        isFocused: Bool = false,
        isMinimized: Bool = false,
        source: WindowDiscoverySource
    ) {
        self.id = id
        self.bundleID = bundleID
        self.appName = appName
        self.windowTitle = windowTitle
        self.processID = processID
        self.windowID = windowID
        self.frame = frame
        self.displayID = displayID
        self.isFocused = isFocused
        self.isMinimized = isMinimized
        self.source = source
    }
}

public struct WindowRegistrySnapshot: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var isAccessibilityTrusted: Bool
    public var notes: [String]
    public var windows: [WindowCandidate]

    public init(
        generatedAt: Date = .now,
        isAccessibilityTrusted: Bool,
        notes: [String] = [],
        windows: [WindowCandidate] = []
    ) {
        self.generatedAt = generatedAt
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.notes = notes
        self.windows = windows
    }
}

public struct AdapterHealthReport: Codable, Equatable, Identifiable, Sendable {
    public var id: String { adapterID }
    public var adapterID: String
    public var health: AdapterHealth
    public var detail: String

    public init(adapterID: String, health: AdapterHealth, detail: String) {
        self.adapterID = adapterID
        self.health = health
        self.detail = detail
    }
}

public struct DiagnosticsSnapshot: Codable, Equatable, Sendable {
    public var refreshedAt: Date
    public var permissions: [PermissionStatus]
    public var buildIdentity: BuildIdentityStatus
    public var adapterHealth: [AdapterHealthReport]
    public var windows: [WindowCandidate]
    public var notes: [String]
    public var stateDirectory: String
    public var logDirectory: String

    public init(
        refreshedAt: Date = .now,
        permissions: [PermissionStatus] = [],
        buildIdentity: BuildIdentityStatus = BuildIdentityStatus(),
        adapterHealth: [AdapterHealthReport] = [],
        windows: [WindowCandidate] = [],
        notes: [String] = [],
        stateDirectory: String = "",
        logDirectory: String = ""
    ) {
        self.refreshedAt = refreshedAt
        self.permissions = permissions
        self.buildIdentity = buildIdentity
        self.adapterHealth = adapterHealth
        self.windows = windows
        self.notes = notes
        self.stateDirectory = stateDirectory
        self.logDirectory = logDirectory
    }
}

public struct PersistedWorkspaceState: Codable, Equatable, Sendable {
    public var workspaces: [Workspace]
    public var selectedWorkspaceID: String?
    public var recentWorkspaceIDs: [String]
    public var adapterStates: [AdapterState]
    public var snapshots: [SessionSnapshot]
    public var updatedAt: Date

    public init(
        workspaces: [Workspace] = [],
        selectedWorkspaceID: String? = nil,
        recentWorkspaceIDs: [String] = [],
        adapterStates: [AdapterState] = [],
        snapshots: [SessionSnapshot] = [],
        updatedAt: Date = .now
    ) {
        self.workspaces = workspaces
        self.selectedWorkspaceID = selectedWorkspaceID
        self.recentWorkspaceIDs = recentWorkspaceIDs
        self.adapterStates = adapterStates
        self.snapshots = snapshots
        self.updatedAt = updatedAt
    }
}

public extension PersistedWorkspaceState {
    static let empty = PersistedWorkspaceState()
}
