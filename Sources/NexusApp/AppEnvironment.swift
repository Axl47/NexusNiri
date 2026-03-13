import Foundation
import Observation
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
    let workspaceStore: JSONWorkspaceStore
    let session: WorkspaceSession
    let windowRegistry: AXWindowRegistry
    let layoutEngine: StripLayoutEngine
    let visibilityCoordinator: VisibilityCoordinator
    let adapterRegistry: AdapterRegistry
    let diagnosticsCenter: DiagnosticsCenter
    let diagnosticsPanelController: DiagnosticsPanelController
    let choreographyService: WindowChoreographyService

    private(set) var diagnosticsSnapshot: DiagnosticsSnapshot
    private var started = false
    private var lastChoreographedWorkspace: Workspace?
    private var lastTransitionSourceWorkspace: Workspace?
    private var lastChoreographySignature: ChoreographySignature?
    private var pendingChoreographyRequest: ChoreographyRequest?
    private var choreographyProcessorTask: Task<Void, Never>?
    private var stageViewportFrame: CGRect?

    init() {
        let workspaceStore = JSONWorkspaceStore()
        self.workspaceStore = workspaceStore
        self.session = WorkspaceSession(store: workspaceStore)
        self.windowRegistry = AXWindowRegistry()
        self.layoutEngine = StripLayoutEngine()
        self.visibilityCoordinator = VisibilityCoordinator()
        self.adapterRegistry = AdapterRegistry()
        self.diagnosticsCenter = DiagnosticsCenter()
        self.diagnosticsPanelController = DiagnosticsPanelController()
        self.choreographyService = WindowChoreographyService(
            windowRegistry: windowRegistry,
            visibilityCoordinator: visibilityCoordinator,
            adapterRegistry: adapterRegistry
        )
        self.diagnosticsSnapshot = DiagnosticsSnapshot(
            stateDirectory: workspaceStore.stateDirectoryURL.path,
            logDirectory: workspaceStore.logDirectoryURL.path
        )

        adapterRegistry.register(GenericAXAdapter())

        let tetherBaseURL = URL(string: "http://127.0.0.1:3773")!
        adapterRegistry.register(TetherAdapter(baseURL: tetherBaseURL))
    }

    func start() async {
        guard !started else { return }
        started = true

        await session.load(seedWorkspaces: AppBootstrap.defaultWorkspaces())
        await refreshDiagnostics()
        session.refreshStatus("Nexus shell ready.")
    }

    func refreshDiagnostics() async {
        let windowSnapshot = try? await windowRegistry.snapshot()
        let adapterHealth = await adapterRegistry.healthReports()
        diagnosticsCenter.refresh(
            stateDirectory: workspaceStore.stateDirectoryURL,
            logDirectory: workspaceStore.logDirectoryURL,
            windowSnapshot: windowSnapshot,
            adapterHealth: adapterHealth
        )
        diagnosticsSnapshot = diagnosticsCenter.snapshot
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
        let signature = ChoreographySignature(
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
            }
        )
        guard signature != lastChoreographySignature else { return }

        pendingChoreographyRequest = ChoreographyRequest(
            workspace: workspace,
            layout: layout,
            signature: signature
        )
        guard choreographyProcessorTask == nil else { return }

        choreographyProcessorTask = Task { @MainActor [weak self] in
            await self?.processPendingChoreography()
        }
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
        stageViewportFrame = frame
    }

    private func processPendingChoreography() async {
        while let request = pendingChoreographyRequest {
            pendingChoreographyRequest = nil

            guard request.signature != lastChoreographySignature else {
                continue
            }

            let previousWorkspace = lastChoreographedWorkspace
            lastTransitionSourceWorkspace = previousWorkspace

            await choreographyService.apply(
                workspace: request.workspace,
                previousWorkspace: previousWorkspace,
                layout: request.layout,
                stageViewportFrame: stageViewportFrame
            )

            lastChoreographySignature = request.signature
            lastChoreographedWorkspace = request.workspace
            await refreshDiagnostics()

            if previousWorkspace?.id == request.workspace.id {
                let activeSlotLabel = request.workspace.orderedSlots[safe: request.layout.activeSlotIndex]?.label ?? "slot"
                session.refreshStatus("Focused \(activeSlotLabel).")
            } else {
                session.refreshStatus("Staged workspace \(request.workspace.name).")
            }
        }

        choreographyProcessorTask = nil

        if pendingChoreographyRequest != nil {
            choreographyProcessorTask = Task { @MainActor [weak self] in
                await self?.processPendingChoreography()
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
}

private struct ChoreographyFrame: Equatable {
    let slotID: String
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

private struct ChoreographyRequest {
    let workspace: Workspace
    let layout: LayoutPlan
    let signature: ChoreographySignature
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
