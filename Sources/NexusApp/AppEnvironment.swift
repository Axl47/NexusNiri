import AppKit
import Foundation
import Observation
import OSLog
import AdapterBus
import Diagnostics
import GenericAXAdapter
import LayoutEngine
import SharedTypes
import StageChrome
import TetherAdapter
import VisibilityEngine
import WindowRegistry
import WorkspaceEngine

@MainActor
@Observable
final class AppEnvironment {
    private static let focusedWindowPollIntervalNanoseconds: UInt64 = 250_000_000
    private static let focusSyncSuppressionDuration: TimeInterval = 0.4
    private static let focusedWindowWidthDebounceDuration: TimeInterval = 0.3
    private static let widthObservationTolerance: Double = 2

    private let focusSyncLogger = Logger(subsystem: "dev.nexusniri.Nexus", category: "focusSync")
    private let slotPresetCatalog: SlotPresetCatalog
    private let workspaceTemplateCatalog: WorkspaceTemplateCatalog
    private let focusedWindowSlotFactory: FocusedWindowSlotFactory
    let workspaceStore: JSONWorkspaceStore
    let session: WorkspaceSession
    let windowRegistry: any WindowRegistryService
    let layoutEngine: StripLayoutEngine
    let visibilityCoordinator: VisibilityCoordinator
    let adapterRegistry: AdapterRegistry
    let diagnosticsCenter: DiagnosticsCenter
    let diagnosticsPanelController: DiagnosticsPanelController
    let choreographyService: any WindowChoreographing
    let stageMaskCoordinator: any StageMaskCoordinating
    let shellWindowManager: any ShellWindowManaging

    private(set) var diagnosticsSnapshot: DiagnosticsSnapshot
    private(set) var shellPresentationMode: ShellPresentationMode
    private(set) var shellDisplayLayout: ShellDisplayLayout?
    private var started = false
    private var lastChoreographedWorkspace: Workspace?
    private var lastTransitionSourceWorkspace: Workspace?
    private var lastChoreographySignature: ChoreographySignature?
    private var pendingChoreographyRequest: ChoreographyRequest?
    private var choreographyProcessorTask: Task<Void, Never>?
    private var stageViewportFrame: CGRect?
    private var latestLayoutContext: LayoutContext?
    private var appActivationObserver: NSObjectProtocol?
    private let windowSlotMatcher = WindowSlotMatcher()
    private var focusedWindowMonitorTask: Task<Void, Never>?
    private var lastFocusedWindowFingerprint: FocusedWindowFingerprint?
    private var pendingFocusedWindowWidthObservation: PendingFocusedWindowWidthObservation?
    private var lastAppliedFocusedWindowWidthObservation: AppliedFocusedWindowWidthObservation?
    private var suppressedFocusSyncUntil: Date?
    private var lastObservedExternalWindowCandidate: WindowCandidate?
    private let userDefaults: UserDefaults
    private var shellPersistenceKey: String
    private weak var shellWindow: NSWindow?

    init(
        workspaceStore: JSONWorkspaceStore = JSONWorkspaceStore(),
        windowRegistry: any WindowRegistryService & WindowControlling = AXWindowRegistry(),
        layoutEngine: StripLayoutEngine = StripLayoutEngine(),
        visibilityCoordinator: VisibilityCoordinator = VisibilityCoordinator(),
        adapterRegistry: AdapterRegistry = AdapterRegistry(),
        diagnosticsCenter: DiagnosticsCenter = DiagnosticsCenter(),
        diagnosticsPanelController: DiagnosticsPanelController = DiagnosticsPanelController(),
        choreographyService: (any WindowChoreographing)? = nil,
        stageMaskCoordinator: (any StageMaskCoordinating)? = nil,
        shellWindowManager: (any ShellWindowManaging)? = nil,
        userDefaults: UserDefaults = .standard,
        registerDefaultAdapters: Bool = true
    ) {
        let initialShellPersistenceKey = ShellPresentationPersistence.key(for: NSScreen.main)
        let slotPresetCatalog = SlotPresetCatalog()

        self.slotPresetCatalog = slotPresetCatalog
        self.workspaceTemplateCatalog = WorkspaceTemplateCatalog(presets: slotPresetCatalog)
        self.focusedWindowSlotFactory = FocusedWindowSlotFactory(presets: slotPresetCatalog)
        self.workspaceStore = workspaceStore
        self.session = WorkspaceSession(store: workspaceStore)
        self.windowRegistry = windowRegistry
        self.layoutEngine = layoutEngine
        self.visibilityCoordinator = visibilityCoordinator
        self.adapterRegistry = adapterRegistry
        self.diagnosticsCenter = diagnosticsCenter
        self.diagnosticsPanelController = diagnosticsPanelController
        self.choreographyService = choreographyService ?? WindowChoreographyService(
            windowRegistry: windowRegistry,
            visibilityCoordinator: visibilityCoordinator,
            adapterRegistry: adapterRegistry
        )
        self.stageMaskCoordinator = stageMaskCoordinator ?? NoopStageMaskCoordinator()
        self.shellWindowManager = shellWindowManager ?? ShellWindowManager()
        self.userDefaults = userDefaults
        self.shellPersistenceKey = initialShellPersistenceKey
        self.shellPresentationMode = Self.loadShellPresentationMode(
            from: userDefaults,
            key: initialShellPersistenceKey
        )
        self.diagnosticsSnapshot = DiagnosticsSnapshot(
            stateDirectory: workspaceStore.stateDirectoryURL.path,
            logDirectory: workspaceStore.logDirectoryURL.path
        )

        if registerDefaultAdapters {
            adapterRegistry.register(GenericAXAdapter())

            let tetherBaseURL = URL(string: "http://127.0.0.1:3773")!
            adapterRegistry.register(TetherAdapter(baseURL: tetherBaseURL))
        }

        appActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshDiagnostics()
            }
        }
    }

    var workspaceTemplateOptions: [WorkspaceTemplateOption] {
        workspaceTemplateCatalog.options
    }

    func start() async {
        guard !started else { return }
        started = true

        await session.load(seedWorkspaces: AppBootstrap.defaultWorkspaces())
        await refreshDiagnostics()
        startFocusedWindowMonitor()
        session.refreshStatus("Nexus shell ready.")
    }

    func refreshDiagnostics() async {
        let wasAccessibilityTrusted = diagnosticsSnapshot.permissions.contains(where: {
            $0.kind == .accessibility && $0.state == .granted
        })
        let windowSnapshot = try? await windowRegistry.snapshot()
        let adapterHealth = await adapterRegistry.healthReports()
        diagnosticsCenter.refresh(
            stateDirectory: workspaceStore.stateDirectoryURL,
            logDirectory: workspaceStore.logDirectoryURL,
            windowSnapshot: windowSnapshot,
            adapterHealth: adapterHealth
        )
        diagnosticsSnapshot = diagnosticsCenter.snapshot

        let isAccessibilityTrusted = diagnosticsSnapshot.permissions.contains(where: {
            $0.kind == .accessibility && $0.state == .granted
        })

        if wasAccessibilityTrusted == false, isAccessibilityTrusted {
            lastChoreographySignature = nil

            if let latestLayoutContext {
                enqueueChoreographyRequest(
                    workspace: latestLayoutContext.workspace,
                    layout: latestLayoutContext.layout,
                    stageViewportFrame: stageViewportFrame,
                    focusPolicy: focusPolicy(for: session.lastSelectionOrigin)
                )
            }
        }
    }

    func openDiagnosticsPanel() {
        Task {
            await refreshDiagnostics()
            diagnosticsPanelController.show(snapshot: diagnosticsSnapshot) { [weak self] in
                guard let self else { return }
                Task {
                    await self.refreshDiagnostics()
                    self.diagnosticsPanelController.update(snapshot: self.diagnosticsSnapshot)
                }
            }
        }
    }

    func applyChoreography(for workspace: Workspace, layout: LayoutPlan) async {
        latestLayoutContext = LayoutContext(workspace: workspace, layout: layout)
        stageMaskCoordinator.update(
            layout: layout,
            stageViewportFrame: stageViewportFrame,
            shellDisplayLayout: shellDisplayLayout,
            shellPresentationMode: shellPresentationMode
        )
        guard stageViewportFrame != nil || layout.visibleSlotIDs.isEmpty else { return }
        enqueueChoreographyRequest(
            workspace: workspace,
            layout: layout,
            stageViewportFrame: stageViewportFrame,
            focusPolicy: focusPolicy(for: session.lastSelectionOrigin)
        )
    }

    func revealAll() {
        Task {
            stageMaskCoordinator.hideAll()
            await choreographyService.revealAll(
                currentWorkspace: lastChoreographedWorkspace ?? session.selectedWorkspace,
                previousWorkspace: lastTransitionSourceWorkspace,
                stageViewportFrame: stageViewportFrame
            )
            await refreshDiagnostics()
            session.refreshStatus("Panic reveal-all enabled. Use slot or workspace navigation to re-stage windows.")
        }
    }

    func updateStageViewportFrame(_ frame: CGRect) {
        refreshShellPresentationIfScreenChanged()

        let integralFrame = frame.integral
        guard integralFrame != stageViewportFrame?.integral else { return }
        stageViewportFrame = integralFrame

        stageMaskCoordinator.update(
            layout: latestLayoutContext?.layout,
            stageViewportFrame: integralFrame,
            shellDisplayLayout: shellDisplayLayout,
            shellPresentationMode: shellPresentationMode
        )
        guard let latestLayoutContext else { return }
        enqueueChoreographyRequest(
            workspace: latestLayoutContext.workspace,
            layout: latestLayoutContext.layout,
            stageViewportFrame: integralFrame,
            focusPolicy: focusPolicy(for: session.lastSelectionOrigin)
        )
    }

    func updateShellWindow(_ window: NSWindow?) {
        guard let window else { return }
        shellWindow = window
        shellWindowManager.attach(window: window)
        stageMaskCoordinator.attach(to: window)
        synchronizeShellPresentation(for: window.screen)
        stageMaskCoordinator.update(
            layout: latestLayoutContext?.layout,
            stageViewportFrame: stageViewportFrame,
            shellDisplayLayout: shellDisplayLayout,
            shellPresentationMode: shellPresentationMode
        )
    }

    func requestAccessibilityAccess() async {
        let granted = diagnosticsCenter.requestAccessibilityAccess()
        await refreshDiagnostics()

        if granted == false {
            diagnosticsCenter.openAccessibilitySettings()
            session.refreshStatus(accessibilityBlockedStatusMessage())
        }
    }

    func toggleShellPresentationMode() {
        let nextMode: ShellPresentationMode = switch shellPresentationMode {
        case .windowed:
            .notchFill
        case .notchFill:
            .windowed
        }

        setShellPresentationMode(nextMode)
    }

    func shellPresentationMenuTitle() -> String {
        switch shellPresentationMode {
        case .windowed:
            "Enter Over-Notch Mode"
        case .notchFill:
            "Exit Over-Notch Mode"
        }
    }

    func createWorkspace(from templateID: String) {
        let nextDefaultName = suggestedWorkspaceName(forTemplateID: templateID)
        guard let workspace = workspaceTemplateCatalog.instantiate(
            templateID: templateID,
            workspaceName: nextDefaultName
        ) else {
            session.refreshStatus("Unable to create workspace from template.")
            return
        }

        session.addWorkspace(workspace)
    }

    func addFocusedWindowToSelectedWorkspace() async {
        guard let workspace = session.selectedWorkspace else {
            session.refreshStatus("Select a workspace before adding a window.")
            return
        }

        guard let candidate = focusedWindowCandidateForExplicitAdd() else {
            session.refreshStatus("Focus an app window, then return to Nexus to add it.")
            return
        }

        if let exactMatch = exactManagedWindowMatch(for: candidate) {
            session.selectWorkspace(id: exactMatch.workspaceID, origin: .nexusNavigation)
            session.selectSlot(id: exactMatch.slotID, origin: .nexusNavigation)
            return
        }

        let existingLabels = Set(workspace.slots.map(\.label))
        guard let slot = focusedWindowSlotFactory.makeSlot(
            from: candidate,
            workspaceID: workspace.id,
            existingLabels: existingLabels
        ) else {
            session.refreshStatus("That window cannot be added to the current workspace.")
            return
        }

        _ = session.addSlot(
            slot,
            to: workspace.id,
            afterSlotID: workspace.activeSlotID,
            selecting: true,
            origin: .nexusNavigation
        )
    }

    func toggleSelectedWorkspaceAutoAdd() {
        _ = session.toggleSelectedWorkspaceAutoAddPolicy()
    }

    private func processPendingChoreography() async {
        while let request = pendingChoreographyRequest {
            pendingChoreographyRequest = nil

            guard request.signature != lastChoreographySignature else {
                continue
            }

            let previousWorkspace = lastChoreographedWorkspace
            lastTransitionSourceWorkspace = previousWorkspace

            if request.focusPolicy == .focusActiveSlot {
                suppressFocusedWindowSync()
            }

            let outcome = await choreographyService.apply(
                workspace: request.workspace,
                previousWorkspace: previousWorkspace,
                layout: request.layout,
                stageViewportFrame: stageViewportFrame,
                focusPolicy: request.focusPolicy
            )

            if request.focusPolicy == .focusActiveSlot {
                suppressFocusedWindowSync()
            }

            latestLayoutContext = LayoutContext(workspace: request.workspace, layout: request.layout)
            lastChoreographySignature = request.signature
            lastChoreographedWorkspace = request.workspace
            await refreshRuntimeBindingsAndVisibleWidths(
                for: request.workspace,
                layout: request.layout
            )
            await refreshDiagnostics()

            switch outcome {
            case .applied:
                if previousWorkspace?.id == request.workspace.id {
                    let activeSlotLabel = request.workspace.orderedSlots[safe: request.layout.activeSlotIndex]?.label ?? "slot"
                    session.refreshStatus("Focused \(activeSlotLabel).")
                } else {
                    session.refreshStatus("Staged workspace \(request.workspace.name).")
                }
            case .blocked(.accessibilityDenied):
                session.refreshStatus(accessibilityBlockedStatusMessage())
            }
        }

        choreographyProcessorTask = nil

        if pendingChoreographyRequest != nil {
            choreographyProcessorTask = Task { @MainActor [weak self] in
                await self?.processPendingChoreography()
            }
        }
    }

    private func choreographySignature(
        for workspace: Workspace,
        layout: LayoutPlan,
        stageViewportFrame: CGRect?
    ) -> ChoreographySignature {
        ChoreographySignature(
            workspaceID: workspace.id,
            activeSlotID: workspace.activeSlotID,
            visibleSlotIDs: layout.visibleSlotIDs,
            contentWidth: Int(layout.contentWidth.rounded()),
            scrollOffset: Int(layout.scrollOffset.rounded()),
            slotFrames: layout.slotLayouts.map { layout in
                ChoreographyFrame(
                    slotID: layout.slotID,
                    x: Int(layout.frame.x.rounded()),
                    y: Int(layout.frame.y.rounded()),
                    width: Int(layout.frame.width.rounded()),
                    height: Int(layout.frame.height.rounded())
                )
            },
            viewportFrame: stageViewportFrame.map {
                ChoreographyViewportFrame(
                    x: Int($0.origin.x.rounded()),
                    y: Int($0.origin.y.rounded()),
                    width: Int($0.size.width.rounded()),
                    height: Int($0.size.height.rounded())
                )
            }
        )
    }

    private func enqueueChoreographyRequest(
        workspace: Workspace,
        layout: LayoutPlan,
        stageViewportFrame: CGRect?,
        focusPolicy: ChoreographyFocusPolicy
    ) {
        let signature = choreographySignature(for: workspace, layout: layout, stageViewportFrame: stageViewportFrame)
        guard signature != lastChoreographySignature else { return }

        pendingChoreographyRequest = ChoreographyRequest(
            workspace: workspace,
            layout: layout,
            signature: signature,
            focusPolicy: focusPolicy
        )
        guard choreographyProcessorTask == nil else { return }

        choreographyProcessorTask = Task { @MainActor [weak self] in
            await self?.processPendingChoreography()
        }
    }

    private func accessibilityBlockedStatusMessage() -> String {
        let buildIdentity = diagnosticsSnapshot.buildIdentity

        if buildIdentity.signingMode == .adHoc {
            return "Window choreography blocked. Rebuild Nexus with NEXUS_CODESIGN_IDENTITY and launch the installed app."
        }

        if let expectedInstallPath = buildIdentity.expectedInstallPath,
           expectedInstallPath.isEmpty == false,
           buildIdentity.launchedFromExpectedPath == false {
            return "Window choreography blocked. Grant Accessibility to the Nexus.app installed at \(expectedInstallPath)."
        }

        return "Window choreography blocked. Grant Accessibility to the running Nexus.app."
    }

    private func setShellPresentationMode(_ mode: ShellPresentationMode) {
        shellPresentationMode = mode
        persistShellPresentationMode(mode, key: shellPersistenceKey)
        synchronizeShellPresentation(
            for: shellWindowManagerCurrentScreen(),
            reloadModeFromPersistence: false
        )
        stageMaskCoordinator.update(
            layout: latestLayoutContext?.layout,
            stageViewportFrame: stageViewportFrame,
            shellDisplayLayout: shellDisplayLayout,
            shellPresentationMode: shellPresentationMode
        )
        session.refreshStatus(
            mode == .notchFill
                ? "Entered Nexus over-notch mode."
                : "Restored Nexus windowed mode."
        )
    }

    private func synchronizeShellPresentation(
        for screen: NSScreen?,
        reloadModeFromPersistence: Bool = true
    ) {
        let nextPersistenceKey = ShellPresentationPersistence.key(for: screen)
        if shellPersistenceKey != nextPersistenceKey {
            shellPersistenceKey = nextPersistenceKey
            if reloadModeFromPersistence {
                shellPresentationMode = Self.loadShellPresentationMode(
                    from: userDefaults,
                    key: nextPersistenceKey
                )
            }
        }

        shellWindowManager.apply(mode: shellPresentationMode, screen: screen)
        shellDisplayLayout = shellWindowManager.currentLayout()
    }

    private func refreshShellPresentationIfScreenChanged() {
        let currentScreen = shellWindowManagerCurrentScreen()
        let nextPersistenceKey = ShellPresentationPersistence.key(for: currentScreen)
        guard nextPersistenceKey != shellPersistenceKey else { return }

        synchronizeShellPresentation(for: currentScreen)
    }

    private func shellWindowManagerCurrentScreen() -> NSScreen? {
        shellWindow?.screen ?? NSScreen.main
    }

    private static func loadShellPresentationMode(from userDefaults: UserDefaults, key: String) -> ShellPresentationMode {
        guard let rawValue = userDefaults.string(forKey: key),
              let mode = ShellPresentationMode(rawValue: rawValue) else {
            return .windowed
        }

        return mode
    }

    private func persistShellPresentationMode(_ mode: ShellPresentationMode, key: String) {
        userDefaults.set(mode.rawValue, forKey: key)
    }

    private func refreshRuntimeBindingsAndVisibleWidths(
        for workspace: Workspace,
        layout: LayoutPlan
    ) async {
        guard let snapshot = try? await windowRegistry.snapshot(),
              snapshot.windows.isEmpty == false else {
            return
        }

        let visibleSlotIDs = Set(layout.visibleSlotIDs)
        let slotLayouts = Dictionary(uniqueKeysWithValues: layout.slotLayouts.map { ($0.slotID, $0) })
        let viewportWidth = stageViewportFrame?.width ?? 0

        for slot in workspace.orderedSlots {
            guard let match = windowSlotMatcher.bestCandidateMatch(
                for: slot,
                preferredWindowID: slot.runtimeBinding?.windowID,
                in: snapshot.windows
            ) else {
                continue
            }

            _ = session.refreshRuntimeBinding(
                workspaceID: workspace.id,
                slotID: slot.id,
                candidate: match.candidate,
                matchConfidence: match.confidence
            )

            guard viewportWidth > 0,
                  visibleSlotIDs.contains(slot.id),
                  let slotLayout = slotLayouts[slot.id] else {
                continue
            }

            _ = reconcileObservedSlotWidth(
                workspaceID: workspace.id,
                slotID: slot.id,
                candidate: match.candidate,
                plannedWidth: slotLayout.frame.width,
                viewportWidth: viewportWidth
            )
        }
    }

    func handleFocusedWindowCandidate(_ candidate: WindowCandidate) async {
        let fingerprint = FocusedWindowFingerprint(candidate: candidate)
        guard fingerprint != lastFocusedWindowFingerprint else { return }
        lastFocusedWindowFingerprint = fingerprint

        guard candidate.isMinimized == false else { return }
        guard isFocusSyncSuppressed == false else { return }
        lastObservedExternalWindowCandidate = candidate

        guard let match = windowSlotMatcher.bestSlotMatch(
            for: candidate,
            in: session.workspaces,
            preferredWorkspaceID: session.selectedWorkspaceID,
            ignoringBundleID: Bundle.main.bundleIdentifier,
            ignoringProcessID: Int(ProcessInfo.processInfo.processIdentifier)
        ) else {
            if await autoAddFocusedWindowIfNeeded(candidate) {
                return
            }
            focusSyncLogger.debug(
                "Reverse focus ignored candidate bundle=\(candidate.bundleID ?? "nil", privacy: .public) pid=\(candidate.processID, privacy: .public) windowID=\(String(describing: candidate.windowID), privacy: .public) title=\(candidate.windowTitle, privacy: .public) source=\(String(describing: candidate.source), privacy: .public) reason=noSlotMatch"
            )
            return
        }

        focusSyncLogger.debug(
            "Reverse focus matched candidate bundle=\(candidate.bundleID ?? "nil", privacy: .public) pid=\(candidate.processID, privacy: .public) windowID=\(String(describing: candidate.windowID), privacy: .public) title=\(candidate.windowTitle, privacy: .public) source=\(String(describing: candidate.source), privacy: .public) workspace=\(match.workspaceID, privacy: .public) slot=\(match.slotID, privacy: .public) confidence=\(match.confidence, privacy: .public)"
        )

        _ = session.syncFocusedWindowMatch(
            workspaceID: match.workspaceID,
            slotID: match.slotID,
            candidate: candidate,
            matchConfidence: match.confidence
        )
    }

    private var isAccessibilityTrusted: Bool {
        diagnosticsSnapshot.permissions.contains {
            $0.kind == .accessibility && $0.state == .granted
        }
    }

    private var isFocusSyncSuppressed: Bool {
        guard let suppressedFocusSyncUntil else { return false }
        return suppressedFocusSyncUntil > .now
    }

    private func suppressFocusedWindowSync() {
        suppressedFocusSyncUntil = Date().addingTimeInterval(Self.focusSyncSuppressionDuration)
    }

    private func focusPolicy(for origin: SelectionOrigin) -> ChoreographyFocusPolicy {
        switch origin {
        case .nexusNavigation:
            return .focusActiveSlot
        case .nativeFocusSync, .nativeGeometrySync:
            return .preserveExternalFocus
        }
    }

    private func startFocusedWindowMonitor() {
        guard focusedWindowMonitorTask == nil else { return }

        focusedWindowMonitorTask = Task { @MainActor [weak self] in
            while let self, Task.isCancelled == false {
                if self.isAccessibilityTrusted,
                   let candidate = try? await self.windowRegistry.focusedWindowCandidate() {
                    await self.handleFocusedWindowCandidate(candidate)
                    self.reconcileFocusedWindowWidth(candidate)
                }

                do {
                    try await Task.sleep(nanoseconds: Self.focusedWindowPollIntervalNanoseconds)
                } catch {
                    break
                }
            }
        }
    }

    @discardableResult
    private func reconcileObservedSlotWidth(
        workspaceID: String,
        slotID: String,
        candidate: WindowCandidate,
        plannedWidth: Double,
        viewportWidth: Double
    ) -> Bool {
        guard candidate.isMinimized == false,
              candidate.frame.width > 0,
              abs(candidate.frame.width - plannedWidth) >= Self.widthObservationTolerance else {
            return false
        }

        return session.refreshSlotWidth(
            workspaceID: workspaceID,
            slotID: slotID,
            observedWidth: candidate.frame.width,
            viewportWidth: viewportWidth
        )
    }

    private func reconcileFocusedWindowWidth(_ candidate: WindowCandidate) {
        guard let stageViewportFrame,
              let latestLayoutContext,
              candidate.isMinimized == false,
              candidate.frame.width > 0 else {
            pendingFocusedWindowWidthObservation = nil
            return
        }

        guard let match = windowSlotMatcher.bestSlotMatch(
            for: candidate,
            in: session.workspaces,
            preferredWorkspaceID: session.selectedWorkspaceID,
            ignoringBundleID: Bundle.main.bundleIdentifier,
            ignoringProcessID: Int(ProcessInfo.processInfo.processIdentifier)
        ),
        match.workspaceID == session.selectedWorkspaceID,
        latestLayoutContext.workspace.id == match.workspaceID,
        latestLayoutContext.layout.visibleSlotIDs.contains(match.slotID),
        let plannedWidth = latestLayoutContext.layout.slotLayouts.first(where: { $0.slotID == match.slotID })?.frame.width else {
            pendingFocusedWindowWidthObservation = nil
            return
        }

        let observation = AppliedFocusedWindowWidthObservation(
            fingerprint: FocusedWindowFingerprint(candidate: candidate),
            workspaceID: match.workspaceID,
            slotID: match.slotID,
            roundedWidth: Int(candidate.frame.width.rounded())
        )

        guard observation != lastAppliedFocusedWindowWidthObservation else { return }

        guard abs(candidate.frame.width - plannedWidth) >= Self.widthObservationTolerance else {
            pendingFocusedWindowWidthObservation = nil
            lastAppliedFocusedWindowWidthObservation = observation
            return
        }

        let now = Date()

        if let pendingFocusedWindowWidthObservation,
           pendingFocusedWindowWidthObservation.matches(observation) {
            let updatedObservation = pendingFocusedWindowWidthObservation.advanced(to: now)
            self.pendingFocusedWindowWidthObservation = updatedObservation

            let isStable = updatedObservation.observationCount >= 2 ||
                now.timeIntervalSince(updatedObservation.firstObservedAt) >= Self.focusedWindowWidthDebounceDuration
            guard isStable else { return }

            _ = session.refreshSlotWidth(
                workspaceID: match.workspaceID,
                slotID: match.slotID,
                observedWidth: candidate.frame.width,
                viewportWidth: stageViewportFrame.width
            )
            lastAppliedFocusedWindowWidthObservation = observation
            self.pendingFocusedWindowWidthObservation = nil
            return
        }

        pendingFocusedWindowWidthObservation = PendingFocusedWindowWidthObservation(
            observation: observation,
            firstObservedAt: now,
            observationCount: 1
        )
    }

    private func suggestedWorkspaceName(forTemplateID templateID: String) -> String? {
        switch templateID {
        case "starter", "blank":
            let existingWorkspaceNumbers = session.workspaces.compactMap { workspace -> Int? in
                guard workspace.name.hasPrefix("Workspace ") else { return nil }
                return Int(workspace.name.dropFirst("Workspace ".count))
            }
            return "Workspace \((existingWorkspaceNumbers.max() ?? 0) + 1)"
        default:
            return nil
        }
    }

    private func focusedWindowCandidateForExplicitAdd() -> WindowCandidate? {
        if let lastObservedExternalWindowCandidate,
           candidateIsAllowedForManagement(lastObservedExternalWindowCandidate) {
            return lastObservedExternalWindowCandidate
        }

        return nil
    }

    private func candidateIsAllowedForManagement(_ candidate: WindowCandidate) -> Bool {
        guard candidate.isMinimized == false else { return false }
        guard let bundleID = SlotPresetCatalog.canonicalBundleID(candidate.bundleID) else { return false }
        guard bundleID != Bundle.main.bundleIdentifier?.lowercased() else { return false }
        return true
    }

    private func exactManagedWindowMatch(
        for candidate: WindowCandidate
    ) -> WindowSlotMatcher.SlotMatch? {
        guard let match = windowSlotMatcher.bestSlotMatch(
            for: candidate,
            in: session.workspaces,
            preferredWorkspaceID: session.selectedWorkspaceID,
            ignoringBundleID: nil,
            ignoringProcessID: -1
        ),
        match.confidence == 1 else {
            return nil
        }

        return match
    }

    private func autoAddFocusedWindowIfNeeded(_ candidate: WindowCandidate) async -> Bool {
        guard candidateIsAllowedForManagement(candidate),
              exactManagedWindowMatch(for: candidate) == nil,
              let workspace = session.selectedWorkspace,
              workspace.autoAddPolicy == .focusedStandardWindow else {
            return false
        }

        let existingLabels = Set(workspace.slots.map(\.label))
        guard let slot = focusedWindowSlotFactory.makeSlot(
            from: candidate,
            workspaceID: workspace.id,
            existingLabels: existingLabels
        ) else {
            return false
        }

        return session.addSlot(
            slot,
            to: workspace.id,
            afterSlotID: workspace.activeSlotID,
            selecting: true,
            origin: .nativeFocusSync
        )
    }
}

private struct ChoreographySignature: Equatable {
    let workspaceID: String
    let activeSlotID: String?
    let visibleSlotIDs: [String]
    let contentWidth: Int
    let scrollOffset: Int
    let slotFrames: [ChoreographyFrame]
    let viewportFrame: ChoreographyViewportFrame?
}

private struct ChoreographyFrame: Equatable {
    let slotID: String
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

private struct ChoreographyViewportFrame: Equatable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

private struct ChoreographyRequest {
    let workspace: Workspace
    let layout: LayoutPlan
    let signature: ChoreographySignature
    let focusPolicy: ChoreographyFocusPolicy
}

private struct LayoutContext {
    let workspace: Workspace
    let layout: LayoutPlan
}

private struct FocusedWindowFingerprint: Equatable {
    let processID: Int
    let windowID: Int?
    let bundleID: String?
    let windowTitle: String

    init(candidate: WindowCandidate) {
        processID = candidate.processID
        windowID = candidate.windowID
        bundleID = candidate.bundleID
        windowTitle = candidate.windowTitle
    }
}

private struct PendingFocusedWindowWidthObservation {
    let observation: AppliedFocusedWindowWidthObservation
    let firstObservedAt: Date
    let observationCount: Int

    func matches(_ other: AppliedFocusedWindowWidthObservation) -> Bool {
        observation == other
    }

    func advanced(to date: Date) -> PendingFocusedWindowWidthObservation {
        PendingFocusedWindowWidthObservation(
            observation: observation,
            firstObservedAt: firstObservedAt,
            observationCount: observationCount + 1
        )
    }
}

private struct AppliedFocusedWindowWidthObservation: Equatable {
    let fingerprint: FocusedWindowFingerprint
    let workspaceID: String
    let slotID: String
    let roundedWidth: Int
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
