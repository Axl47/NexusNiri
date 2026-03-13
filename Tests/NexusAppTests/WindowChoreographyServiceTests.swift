import AdapterBus
import Foundation
import LayoutEngine
import SharedTypes
import Testing
import VisibilityEngine
import WorkspaceEngine
@testable import NexusApp

@MainActor
@Test
func visibleSlotStagingWritesFramesForEachVisibleWindowAndFocusesOnlyAtTheEnd() async throws {
    let registry = RecordingWindowRegistry(
        snapshot: WindowRegistrySnapshot(
            isAccessibilityTrusted: true,
            windows: [
                WindowCandidate(
                    bundleID: "com.example.editor",
                    appName: "Editor",
                    windowTitle: "Project",
                    processID: 101,
                    windowID: 1,
                    frame: .zero,
                    source: .accessibility
                ),
                WindowCandidate(
                    bundleID: "com.example.browser",
                    appName: "Browser",
                    windowTitle: "Docs",
                    processID: 202,
                    windowID: 2,
                    frame: .zero,
                    source: .accessibility
                ),
            ]
        )
    )
    let service = WindowChoreographyService(
        windowRegistry: registry,
        visibilityCoordinator: VisibilityCoordinator(),
        adapterRegistry: AdapterRegistry()
    )
    let slots = [
        Slot(
            id: "editor",
            workspaceID: "workspace",
            kind: .externalWindow,
            label: "Editor",
            appBinding: AppBinding(bundleID: "com.example.editor"),
            widthPolicy: SizePolicy(mode: .fraction, value: 0.6),
            layoutRole: .primary
        ),
        Slot(
            id: "browser",
            workspaceID: "workspace",
            kind: .externalWindow,
            label: "Browser",
            appBinding: AppBinding(bundleID: "com.example.browser"),
            widthPolicy: SizePolicy(mode: .fraction, value: 0.4),
            layoutRole: .secondary
        ),
    ]
    let workspace = Workspace(
        id: "workspace",
        name: "Main",
        activeSlotID: "editor",
        slotOrder: slots.map(\.id),
        layoutState: LayoutState(activeIndex: 0, centeredSlotID: "editor", visibleSlotIDs: slots.map(\.id)),
        slots: slots
    )
    let layout = LayoutPlan(
        slotLayouts: [
            SlotLayout(slotID: "editor", frame: RectValue(x: 0, y: 0, width: 720, height: 640), isFocused: true),
            SlotLayout(slotID: "browser", frame: RectValue(x: 722, y: 0, width: 478, height: 640), isFocused: false),
        ],
        contentWidth: 1200,
        scrollOffset: 0,
        visibleSlotIDs: ["editor", "browser"],
        parkedSlotIDs: [],
        activeSlotIndex: 0
    )
    let viewportFrame = CGRect(x: 100, y: 200, width: 1200, height: 720)

    await service.apply(
        workspace: workspace,
        previousWorkspace: nil,
        layout: layout,
        stageViewportFrame: viewportFrame
    )

    let operations = registry.operations
    let frameOperations = operations.compactMap { operation -> RecordingWindowRegistry.Operation? in
        if case .setFrame = operation {
            return operation
        }
        return nil
    }

    #expect(frameOperations.count == 2)
    #expect(frameOperations.contains(.setFrame(processID: 101, windowID: 1, frame: RectValue(x: 100, y: 892, width: 720, height: 640))))
    #expect(frameOperations.contains(.setFrame(processID: 202, windowID: 2, frame: RectValue(x: 822, y: 892, width: 478, height: 640))))

    let focusOperations = operations.compactMap { operation -> RecordingWindowRegistry.Operation? in
        if case .focus = operation {
            return operation
        }
        return nil
    }

    #expect(focusOperations == [.focus(processID: 101, windowID: 1)])
    let lastFrameIndex = try #require(operations.lastIndex(where: { operation in
        if case .setFrame = operation {
            return true
        }
        return false
    }))
    let focusIndex = try #require(operations.firstIndex(of: .focus(processID: 101, windowID: 1)))
    #expect(focusIndex > lastFrameIndex)
}

@MainActor
@Test
func appEnvironmentRestagesWhenViewportFrameChangesButNotWhenItRepeats() async throws {
    let registry = RecordingWindowRegistry(snapshot: WindowRegistrySnapshot(isAccessibilityTrusted: false))
    let choreographyService = RecordingChoreographyService()
    let environment = AppEnvironment(
        windowRegistry: registry,
        adapterRegistry: AdapterRegistry(),
        choreographyService: choreographyService,
        registerDefaultAdapters: false
    )
    let slot = Slot(
        id: "editor",
        workspaceID: "workspace",
        kind: .externalWindow,
        label: "Editor",
        appBinding: AppBinding(bundleID: "com.example.editor"),
        widthPolicy: SizePolicy(mode: .fraction, value: 0.6),
        layoutRole: .primary
    )
    let workspace = Workspace(
        id: "workspace",
        name: "Main",
        activeSlotID: "editor",
        slotOrder: [slot.id],
        layoutState: LayoutState(activeIndex: 0, centeredSlotID: slot.id, visibleSlotIDs: [slot.id]),
        slots: [slot]
    )
    let layout = LayoutPlan(
        slotLayouts: [
            SlotLayout(slotID: slot.id, frame: RectValue(x: 0, y: 0, width: 720, height: 640), isFocused: true),
        ],
        contentWidth: 720,
        scrollOffset: 0,
        visibleSlotIDs: [slot.id],
        parkedSlotIDs: [],
        activeSlotIndex: 0
    )

    await environment.applyChoreography(for: workspace, layout: layout)
    try await waitForApplyCount(1, service: choreographyService)

    environment.updateStageViewportFrame(CGRect(x: 100, y: 200, width: 1200, height: 720))
    try await waitForApplyCount(2, service: choreographyService)

    environment.updateStageViewportFrame(CGRect(x: 100, y: 200, width: 1200, height: 720))
    try await Task.sleep(nanoseconds: 50_000_000)

    #expect(choreographyService.applyCalls.count == 2)
}

@MainActor
private func waitForApplyCount(_ expectedCount: Int, service: RecordingChoreographyService) async throws {
    for _ in 0..<50 {
        if service.applyCalls.count == expectedCount {
            return
        }
        await Task.yield()
        try await Task.sleep(nanoseconds: 10_000_000)
    }

    Issue.record("Timed out waiting for \(expectedCount) choreography apply call(s); saw \(service.applyCalls.count).")
    throw TestFailure()
}

private final class RecordingWindowRegistry: @unchecked Sendable, WindowRegistryService, WindowControlling {
    enum Operation: Equatable {
        case setFrame(processID: Int, windowID: Int?, frame: RectValue)
        case setMinimized(processID: Int, windowID: Int?, minimized: Bool)
        case setHidden(processID: Int, hidden: Bool)
        case activate(processID: Int)
        case raise(processID: Int, windowID: Int?)
        case focus(processID: Int, windowID: Int?)
    }

    private let snapshotValue: WindowRegistrySnapshot
    private(set) var operations: [Operation] = []

    init(snapshot: WindowRegistrySnapshot) {
        self.snapshotValue = snapshot
    }

    func snapshot() async throws -> WindowRegistrySnapshot {
        snapshotValue
    }

    func setWindowFrame(processID: Int, windowID: Int?, to frame: RectValue) async throws {
        operations.append(.setFrame(processID: processID, windowID: windowID, frame: frame))
    }

    func setWindowMinimized(processID: Int, windowID: Int?, to minimized: Bool) async throws {
        operations.append(.setMinimized(processID: processID, windowID: windowID, minimized: minimized))
    }

    func setApplicationHidden(processID: Int, to hidden: Bool) async throws {
        operations.append(.setHidden(processID: processID, hidden: hidden))
    }

    func activateApplication(processID: Int) async throws {
        operations.append(.activate(processID: processID))
    }

    func raiseWindow(processID: Int, windowID: Int?) async throws {
        operations.append(.raise(processID: processID, windowID: windowID))
    }

    func focusWindow(processID: Int, windowID: Int?) async throws {
        operations.append(.focus(processID: processID, windowID: windowID))
    }
}

@MainActor
private final class RecordingChoreographyService: WindowChoreographing {
    struct ApplyCall: Equatable {
        let workspaceID: String
        let frame: CGRect?
    }

    private(set) var applyCalls: [ApplyCall] = []

    func apply(
        workspace: Workspace,
        previousWorkspace: Workspace?,
        layout: LayoutPlan,
        stageViewportFrame: CGRect?
    ) async {
        _ = previousWorkspace
        _ = layout
        applyCalls.append(ApplyCall(workspaceID: workspace.id, frame: stageViewportFrame?.integral))
    }

    func revealAll(
        currentWorkspace: Workspace?,
        previousWorkspace: Workspace?,
        stageViewportFrame: CGRect?
    ) async {
        _ = currentWorkspace
        _ = previousWorkspace
        _ = stageViewportFrame
    }
}

private struct TestFailure: Error {}
