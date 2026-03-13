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

    private let focusSyncLogger = Logger(subsystem: "dev.nexusniri.Nexus", category: "focusSync")
    let workspaceStore: JSONWorkspaceStore
    let session: WorkspaceSession
    let windowRegistry: any WindowRegistryService
    let layoutEngine: StripLayoutEngine
    let visibilityCoordinator: VisibilityCoordinator
    let adapterRegistry: AdapterRegistry
    let diagnosticsCenter: DiagnosticsCenter
    let diagnosticsPanelController: DiagnosticsPanelController
    let choreographyService: any WindowChoreographing

    private(set) var diagnosticsSnapshot: DiagnosticsSnapshot
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
    private var suppressedFocusSyncUntil: Date?

    init(
        workspaceStore: JSONWorkspaceStore = JSONWorkspaceStore(),
        windowRegistry: any WindowRegistryService & WindowControlling = AXWindowRegistry(),
        layoutEngine: StripLayoutEngine = StripLayoutEngine(),
        visibilityCoordinator: VisibilityCoordinator = VisibilityCoordinator(),
        adapterRegistry: AdapterRegistry = AdapterRegistry(),
        diagnosticsCenter: DiagnosticsCenter = DiagnosticsCenter(),
        diagnosticsPanelController: DiagnosticsPanelController = DiagnosticsPanelController(),
        choreographyService: (any WindowChoreographing)? = nil,
        registerDefaultAdapters: Bool = true
    ) {
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
        let integralFrame = frame.integral
        guard integralFrame != stageViewportFrame?.integral else { return }
        stageViewportFrame = integralFrame

        guard let latestLayoutContext else { return }
        enqueueChoreographyRequest(
            workspace: latestLayoutContext.workspace,
            layout: latestLayoutContext.layout,
            stageViewportFrame: integralFrame,
            focusPolicy: focusPolicy(for: session.lastSelectionOrigin)
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
            await refreshRuntimeBindings(for: request.workspace)
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

    private func refreshRuntimeBindings(for workspace: Workspace) async {
        guard let snapshot = try? await windowRegistry.snapshot(),
              snapshot.windows.isEmpty == false else {
            return
        }

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
        }
    }

    func handleFocusedWindowCandidate(_ candidate: WindowCandidate) async {
        let fingerprint = FocusedWindowFingerprint(candidate: candidate)
        guard fingerprint != lastFocusedWindowFingerprint else { return }
        lastFocusedWindowFingerprint = fingerprint

        guard candidate.isMinimized == false else { return }
        guard isFocusSyncSuppressed == false else { return }

        guard let match = windowSlotMatcher.bestSlotMatch(
            for: candidate,
            in: session.workspaces,
            preferredWorkspaceID: session.selectedWorkspaceID,
            ignoringBundleID: Bundle.main.bundleIdentifier,
            ignoringProcessID: Int(ProcessInfo.processInfo.processIdentifier)
        ) else {
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
        case .nativeFocusSync:
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
                }

                do {
                    try await Task.sleep(nanoseconds: Self.focusedWindowPollIntervalNanoseconds)
                } catch {
                    break
                }
            }
        }
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

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
