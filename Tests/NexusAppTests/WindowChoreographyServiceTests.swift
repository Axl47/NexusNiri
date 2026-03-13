import AdapterBus
import AppKit
import Diagnostics
import Foundation
import LayoutEngine
import SharedTypes
import StageChrome
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

    let outcome = await service.apply(
        workspace: workspace,
        previousWorkspace: nil,
        layout: layout,
        stageViewportFrame: viewportFrame,
        focusPolicy: .focusActiveSlot
    )
    #expect(outcome == .applied)

    let operations = registry.operations
    let frameOperations = operations.compactMap { operation -> RecordingWindowRegistry.Operation? in
        if case .setFrame = operation {
            return operation
        }
        return nil
    }

    let screenFrame = (NSScreen.screens.max { lhs, rhs in
        lhs.frame.intersection(viewportFrame).area < rhs.frame.intersection(viewportFrame).area
    } ?? NSScreen.main)?.frame ?? CGRect(x: 0, y: 0, width: 1512, height: 982)
    let expectedTopEdge = viewportFrame.maxY - ChromeMetrics.slotHeaderHeight
    let expectedAXY = Double(screenFrame.maxY - expectedTopEdge)

    #expect(frameOperations.count == 2)
    #expect(frameOperations.contains(.setFrame(processID: 101, windowID: 1, frame: RectValue(x: 100, y: expectedAXY, width: 720, height: 640))))
    #expect(frameOperations.contains(.setFrame(processID: 202, windowID: 2, frame: RectValue(x: 822, y: expectedAXY, width: 478, height: 640))))
    #expect(operations.contains(.activate(processID: 101)))
    #expect(operations.contains(.activate(processID: 202)))

    let raiseOperations = operations.compactMap { operation -> RecordingWindowRegistry.Operation? in
        if case .raise = operation {
            return operation
        }
        return nil
    }

    #expect(raiseOperations.contains(.raise(processID: 101, windowID: 1)))
    #expect(raiseOperations.contains(.raise(processID: 202, windowID: 2)))

    let focusOperations = operations.compactMap { operation -> RecordingWindowRegistry.Operation? in
        if case .focus = operation {
            return operation
        }
        return nil
    }

    #expect(focusOperations == [.focus(processID: 101, windowID: 1)])
    let lastRefloatIndex = try #require(operations.lastIndex(where: { operation in
        if case .activate = operation {
            return true
        }
        if case .raise = operation {
            return true
        }
        return false
    }))
    let focusIndex = try #require(operations.firstIndex(of: .focus(processID: 101, windowID: 1)))
    #expect(focusIndex > lastRefloatIndex)
}

@MainActor
@Test
func focusActiveSlotRefloatsVisibleWindowsBeforeFinalFocus() async throws {
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
        activeSlotID: "browser",
        slotOrder: slots.map(\.id),
        layoutState: LayoutState(activeIndex: 1, centeredSlotID: "browser", visibleSlotIDs: slots.map(\.id)),
        slots: slots
    )
    let layout = LayoutPlan(
        slotLayouts: [
            SlotLayout(slotID: "editor", frame: RectValue(x: 0, y: 0, width: 720, height: 640), isFocused: false),
            SlotLayout(slotID: "browser", frame: RectValue(x: 722, y: 0, width: 478, height: 640), isFocused: true),
        ],
        contentWidth: 1200,
        scrollOffset: 0,
        visibleSlotIDs: ["editor", "browser"],
        parkedSlotIDs: [],
        activeSlotIndex: 1
    )

    let outcome = await service.apply(
        workspace: workspace,
        previousWorkspace: nil,
        layout: layout,
        stageViewportFrame: CGRect(x: 100, y: 200, width: 1200, height: 720),
        focusPolicy: .focusActiveSlot
    )

    #expect(outcome == .applied)
    #expect(registry.operations.contains(.activate(processID: 101)))
    #expect(registry.operations.contains(.activate(processID: 202)))
    #expect(registry.operations.contains(.raise(processID: 101, windowID: 1)))
    #expect(registry.operations.contains(.raise(processID: 202, windowID: 2)))
    let focusIndex = try #require(registry.operations.firstIndex(of: .focus(processID: 202, windowID: 2)))
    let lastRefloatIndex = try #require(registry.operations.lastIndex(where: { operation in
        if case .activate = operation {
            return true
        }
        if case .raise = operation {
            return true
        }
        return false
    }))
    #expect(focusIndex > lastRefloatIndex)
}

@MainActor
@Test
func paddedLeadingLayoutStagesFirstSlotAtCenteredScreenPosition() async throws {
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
        Slot(id: "editor", workspaceID: "workspace", kind: .externalWindow, label: "Editor", appBinding: AppBinding(bundleID: "com.example.editor"), widthPolicy: SizePolicy(mode: .fixed, value: 700), layoutRole: .primary),
        Slot(id: "browser", workspaceID: "workspace", kind: .externalWindow, label: "Browser", appBinding: AppBinding(bundleID: "com.example.browser"), widthPolicy: SizePolicy(mode: .fixed, value: 600), layoutRole: .secondary),
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
            SlotLayout(slotID: "editor", frame: RectValue(x: 250, y: 0, width: 700, height: 640), isFocused: true),
            SlotLayout(slotID: "browser", frame: RectValue(x: 952, y: 0, width: 600, height: 640), isFocused: false),
        ],
        contentWidth: 1902,
        scrollOffset: 0,
        leadingPadding: 250,
        trailingPadding: 300,
        visibleSlotIDs: ["editor", "browser"],
        parkedSlotIDs: [],
        activeSlotIndex: 0
    )
    let viewportFrame = CGRect(x: 100, y: 200, width: 1200, height: 720)

    _ = await service.apply(
        workspace: workspace,
        previousWorkspace: nil,
        layout: layout,
        stageViewportFrame: viewportFrame,
        focusPolicy: .focusActiveSlot
    )

    let screenFrame = (NSScreen.screens.max { lhs, rhs in
        lhs.frame.intersection(viewportFrame).area < rhs.frame.intersection(viewportFrame).area
    } ?? NSScreen.main)?.frame ?? CGRect(x: 0, y: 0, width: 1512, height: 982)
    let expectedTopEdge = viewportFrame.maxY - ChromeMetrics.slotHeaderHeight
    let expectedAXY = Double(screenFrame.maxY - expectedTopEdge)

    #expect(registry.operations.contains(.setFrame(processID: 101, windowID: 1, frame: RectValue(x: 350, y: expectedAXY, width: 700, height: 640))))
    #expect(registry.operations.contains(.setFrame(processID: 202, windowID: 2, frame: RectValue(x: 1052, y: expectedAXY, width: 600, height: 640))))
}

@MainActor
@Test
func paddedTrailingLayoutStagesLastSlotAtCenteredScreenPosition() async throws {
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
        Slot(id: "editor", workspaceID: "workspace", kind: .externalWindow, label: "Editor", appBinding: AppBinding(bundleID: "com.example.editor"), widthPolicy: SizePolicy(mode: .fixed, value: 700), layoutRole: .primary),
        Slot(id: "browser", workspaceID: "workspace", kind: .externalWindow, label: "Browser", appBinding: AppBinding(bundleID: "com.example.browser"), widthPolicy: SizePolicy(mode: .fixed, value: 600), layoutRole: .secondary),
    ]
    let workspace = Workspace(
        id: "workspace",
        name: "Main",
        activeSlotID: "browser",
        slotOrder: slots.map(\.id),
        layoutState: LayoutState(activeIndex: 1, centeredSlotID: "browser", visibleSlotIDs: slots.map(\.id)),
        slots: slots
    )
    let layout = LayoutPlan(
        slotLayouts: [
            SlotLayout(slotID: "editor", frame: RectValue(x: 250, y: 0, width: 700, height: 640), isFocused: false),
            SlotLayout(slotID: "browser", frame: RectValue(x: 952, y: 0, width: 600, height: 640), isFocused: true),
        ],
        contentWidth: 1902,
        scrollOffset: 702,
        leadingPadding: 250,
        trailingPadding: 300,
        visibleSlotIDs: ["editor", "browser"],
        parkedSlotIDs: [],
        activeSlotIndex: 1
    )
    let viewportFrame = CGRect(x: 100, y: 200, width: 1200, height: 720)

    _ = await service.apply(
        workspace: workspace,
        previousWorkspace: nil,
        layout: layout,
        stageViewportFrame: viewportFrame,
        focusPolicy: .focusActiveSlot
    )

    let screenFrame = (NSScreen.screens.max { lhs, rhs in
        lhs.frame.intersection(viewportFrame).area < rhs.frame.intersection(viewportFrame).area
    } ?? NSScreen.main)?.frame ?? CGRect(x: 0, y: 0, width: 1512, height: 982)
    let expectedTopEdge = viewportFrame.maxY - ChromeMetrics.slotHeaderHeight
    let expectedAXY = Double(screenFrame.maxY - expectedTopEdge)

    #expect(registry.operations.contains(.setFrame(processID: 101, windowID: 1, frame: RectValue(x: -352, y: expectedAXY, width: 700, height: 640))))
    #expect(registry.operations.contains(.setFrame(processID: 202, windowID: 2, frame: RectValue(x: 350, y: expectedAXY, width: 600, height: 640))))
}

private extension CGRect {
    var area: CGFloat {
        guard isNull == false, isEmpty == false else { return 0 }
        return width * height
    }
}

@MainActor
@Test
func choreographyReturnsBlockedWhenAccessibilityIsDeniedForGenericWindows() async throws {
    let registry = RecordingWindowRegistry(
        snapshot: WindowRegistrySnapshot(
            isAccessibilityTrusted: false,
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
            ]
        )
    )
    let service = WindowChoreographyService(
        windowRegistry: registry,
        visibilityCoordinator: VisibilityCoordinator(),
        adapterRegistry: AdapterRegistry()
    )
    let slot = Slot(
        id: "editor",
        workspaceID: "workspace",
        kind: .externalWindow,
        label: "Editor",
        appBinding: AppBinding(bundleID: "com.example.editor"),
        widthPolicy: SizePolicy(mode: .fraction, value: 1),
        layoutRole: .primary
    )
    let workspace = Workspace(
        id: "workspace",
        name: "Main",
        activeSlotID: slot.id,
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

    let outcome = await service.apply(
        workspace: workspace,
        previousWorkspace: nil,
        layout: layout,
        stageViewportFrame: CGRect(x: 100, y: 200, width: 1200, height: 720),
        focusPolicy: .focusActiveSlot
    )

    #expect(outcome == .blocked(.accessibilityDenied))
    #expect(registry.operations.isEmpty)
}

@MainActor
@Test
func preserveExternalFocusRefloatsVisibleWindowsAndRestoresClickedFocus() async throws {
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
    registry.focusedCandidate = WindowCandidate(
        bundleID: "com.example.browser",
        appName: "Browser",
        windowTitle: "Docs",
        processID: 202,
        windowID: 2,
        frame: .zero,
        source: .accessibility
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
        activeSlotID: "browser",
        slotOrder: slots.map(\.id),
        layoutState: LayoutState(activeIndex: 1, centeredSlotID: "browser", visibleSlotIDs: slots.map(\.id)),
        slots: slots
    )
    let layout = LayoutPlan(
        slotLayouts: [
            SlotLayout(slotID: "editor", frame: RectValue(x: 0, y: 0, width: 720, height: 640), isFocused: false),
            SlotLayout(slotID: "browser", frame: RectValue(x: 722, y: 0, width: 478, height: 640), isFocused: true),
        ],
        contentWidth: 1200,
        scrollOffset: 0,
        visibleSlotIDs: ["editor", "browser"],
        parkedSlotIDs: [],
        activeSlotIndex: 1
    )

    let outcome = await service.apply(
        workspace: workspace,
        previousWorkspace: nil,
        layout: layout,
        stageViewportFrame: CGRect(x: 100, y: 200, width: 1200, height: 720),
        focusPolicy: .preserveExternalFocus
    )

    #expect(outcome == .applied)
    #expect(registry.operations.contains(where: { operation in
        if case .setFrame(processID: 101, windowID: 1, frame: _) = operation {
            return true
        }
        return false
    }))
    #expect(registry.operations.contains(where: { operation in
        if case .setFrame(processID: 202, windowID: 2, frame: _) = operation {
            return true
        }
        return false
    }))
    #expect(registry.operations.contains(.activate(processID: 101)))
    #expect(registry.operations.contains(.raise(processID: 101, windowID: 1)))
    #expect(registry.operations.contains(.activate(processID: 202)))
    #expect(registry.operations.contains(.raise(processID: 202, windowID: 2)))
    #expect(registry.operations.last == .focus(processID: 202, windowID: 2))
}

@MainActor
@Test
func adapterManagedParkAlsoFallsBackToNativeMinimize() async throws {
    let registry = RecordingWindowRegistry(
        snapshot: WindowRegistrySnapshot(
            isAccessibilityTrusted: true,
            windows: [
                WindowCandidate(
                    bundleID: "com.t3tools.tether",
                    appName: "Tether",
                    windowTitle: "RightTether",
                    processID: 303,
                    windowID: 3,
                    frame: .zero,
                    source: .accessibility
                ),
            ]
        )
    )
    let adapterRegistry = AdapterRegistry()
    let adapter = RecordingAdapter(id: "tether", supportedBundleIDs: ["com.t3tools.tether"])
    adapterRegistry.register(adapter)
    let service = WindowChoreographyService(
        windowRegistry: registry,
        visibilityCoordinator: VisibilityCoordinator(),
        adapterRegistry: adapterRegistry
    )
    let slot = Slot(
        id: "tether",
        workspaceID: "workspace",
        kind: .externalWindow,
        label: "RightTether",
        appBinding: AppBinding(bundleID: "com.t3tools.tether"),
        widthPolicy: SizePolicy(mode: .fraction, value: 0.4),
        layoutRole: .secondary,
        adapterID: "tether"
    )
    let workspace = Workspace(
        id: "workspace",
        name: "Main",
        activeSlotID: nil,
        slotOrder: [slot.id],
        layoutState: LayoutState(activeIndex: 0, centeredSlotID: nil, visibleSlotIDs: [], parkedSlotIDs: [slot.id]),
        slots: [slot]
    )
    let layout = LayoutPlan(
        slotLayouts: [],
        contentWidth: 0,
        scrollOffset: 0,
        visibleSlotIDs: [],
        parkedSlotIDs: [slot.id],
        activeSlotIndex: 0
    )

    let outcome = await service.apply(
        workspace: workspace,
        previousWorkspace: nil,
        layout: layout,
        stageViewportFrame: CGRect(x: 100, y: 200, width: 1200, height: 720),
        focusPolicy: .preserveExternalFocus
    )

    #expect(outcome == .applied)
    #expect(adapter.parkedSlotIDs == [slot.id])
    #expect(registry.operations.contains(.setMinimized(processID: 303, windowID: 3, minimized: true)))
}

@MainActor
@Test
func appEnvironmentRestagesWhenViewportFrameChangesButNotWhenItRepeats() async throws {
    let registry = RecordingWindowRegistry(snapshot: WindowRegistrySnapshot(isAccessibilityTrusted: false))
    let choreographyService = RecordingChoreographyService()
    let store = makeWorkspaceStore("AppEnvironmentViewportReplay")
    let environment = AppEnvironment(
        workspaceStore: store,
        windowRegistry: registry,
        adapterRegistry: AdapterRegistry(),
        diagnosticsCenter: DiagnosticsCenter(initialSnapshot: trustedDiagnosticsSnapshot()),
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

    environment.updateStageViewportFrame(CGRect(x: 100, y: 200, width: 1200, height: 720))
    await environment.applyChoreography(for: workspace, layout: layout)
    try await waitForMinimumApplyCount(1, service: choreographyService)
    let initialApplyCount = choreographyService.applyCalls.count

    environment.updateStageViewportFrame(CGRect(x: 140, y: 240, width: 1200, height: 720))
    try await waitForMinimumApplyCount(initialApplyCount + 1, service: choreographyService)
    let postMoveApplyCount = choreographyService.applyCalls.count

    environment.updateStageViewportFrame(CGRect(x: 140, y: 240, width: 1200, height: 720))
    try await Task.sleep(nanoseconds: 50_000_000)

    #expect(choreographyService.applyCalls.count == postMoveApplyCount)
}

@MainActor
@Test
func appEnvironmentFansLayoutStateOutToStageMasksAndRevealAllHidesThem() async throws {
    let registry = RecordingWindowRegistry(snapshot: WindowRegistrySnapshot(isAccessibilityTrusted: false))
    let choreographyService = RecordingChoreographyService()
    let stageMaskCoordinator = RecordingStageMaskCoordinator()
    let store = makeWorkspaceStore("AppEnvironmentStageMasks")
    let environment = AppEnvironment(
        workspaceStore: store,
        windowRegistry: registry,
        adapterRegistry: AdapterRegistry(),
        diagnosticsCenter: DiagnosticsCenter(initialSnapshot: trustedDiagnosticsSnapshot()),
        choreographyService: choreographyService,
        stageMaskCoordinator: stageMaskCoordinator,
        registerDefaultAdapters: false
    )
    let slot = Slot(
        id: "editor",
        workspaceID: "workspace",
        kind: .externalWindow,
        label: "Editor",
        appBinding: AppBinding(bundleID: "com.example.editor"),
        widthPolicy: SizePolicy(mode: .fraction, value: 1),
        layoutRole: .primary
    )
    let workspace = Workspace(
        id: "workspace",
        name: "Main",
        activeSlotID: slot.id,
        slotOrder: [slot.id],
        layoutState: LayoutState(activeIndex: 0, centeredSlotID: slot.id, visibleSlotIDs: [slot.id]),
        slots: [slot]
    )
    let layout = LayoutPlan(
        slotLayouts: [SlotLayout(slotID: slot.id, frame: RectValue(x: 120, y: 0, width: 720, height: 640), isFocused: true)],
        contentWidth: 960,
        scrollOffset: 0,
        leadingPadding: 120,
        trailingPadding: 120,
        visibleSlotIDs: [slot.id],
        parkedSlotIDs: [],
        activeSlotIndex: 0,
        occlusionBands: [RectValue(x: 0, y: 0, width: 120, height: 640)]
    )

    await environment.applyChoreography(for: workspace, layout: layout)
    #expect(stageMaskCoordinator.updateCalls.count == 1)
    #expect(stageMaskCoordinator.updateCalls.last?.frame == nil)

    environment.updateShellWindow(NSWindow())
    #expect(stageMaskCoordinator.attachedWindowWasSet)
    #expect(stageMaskCoordinator.updateCalls.count == 2)

    environment.updateStageViewportFrame(CGRect(x: 100, y: 200, width: 1200, height: 720))
    #expect(stageMaskCoordinator.updateCalls.count == 3)
    #expect(stageMaskCoordinator.updateCalls.last?.frame?.integral == CGRect(x: 100, y: 200, width: 1200, height: 720))
    #expect(stageMaskCoordinator.updateCalls.last?.occlusionBands == [RectValue(x: 0, y: 0, width: 120, height: 640)])

    environment.revealAll()
    try await Task.sleep(nanoseconds: 50_000_000)
    #expect(stageMaskCoordinator.hideAllCount == 1)
}

@MainActor
@Test
func appEnvironmentWaitsForViewportFrameBeforeFirstVisibleSlotApply() async throws {
    let registry = RecordingWindowRegistry(snapshot: WindowRegistrySnapshot(isAccessibilityTrusted: false))
    let choreographyService = RecordingChoreographyService()
    let store = makeWorkspaceStore("AppEnvironmentViewportGate")
    let environment = AppEnvironment(
        workspaceStore: store,
        windowRegistry: registry,
        adapterRegistry: AdapterRegistry(),
        diagnosticsCenter: DiagnosticsCenter(initialSnapshot: trustedDiagnosticsSnapshot()),
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
        activeSlotID: slot.id,
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
    try await Task.sleep(nanoseconds: 50_000_000)
    #expect(choreographyService.applyCalls.isEmpty)

    environment.updateStageViewportFrame(CGRect(x: 100, y: 200, width: 1200, height: 720))
    try await waitForMinimumApplyCount(1, service: choreographyService)
}

@MainActor
@Test
func appEnvironmentReverseFocusSyncUsesPreserveExternalFocus() async throws {
    let registry = RecordingWindowRegistry(snapshot: WindowRegistrySnapshot(isAccessibilityTrusted: true))
    let choreographyService = RecordingChoreographyService()
    let store = makeWorkspaceStore("AppEnvironmentReverseFocusPolicy")
    let environment = AppEnvironment(
        workspaceStore: store,
        windowRegistry: registry,
        adapterRegistry: AdapterRegistry(),
        diagnosticsCenter: DiagnosticsCenter(initialSnapshot: trustedDiagnosticsSnapshot()),
        choreographyService: choreographyService,
        registerDefaultAdapters: false
    )
    let slot = Slot(
        id: "editor",
        workspaceID: "workspace",
        kind: .externalWindow,
        label: "Editor",
        appBinding: AppBinding(bundleID: "com.example.editor"),
        widthPolicy: SizePolicy(mode: .fraction, value: 1),
        layoutRole: .primary,
        runtimeBinding: RuntimeBinding(processID: 101, windowID: 1, matchConfidence: 1)
    )
    let workspace = Workspace(
        id: "workspace",
        name: "Main",
        activeSlotID: slot.id,
        slotOrder: [slot.id],
        layoutState: LayoutState(activeIndex: 0, centeredSlotID: slot.id, visibleSlotIDs: [slot.id]),
        slots: [slot]
    )
    let layout = LayoutPlan(
        slotLayouts: [SlotLayout(slotID: slot.id, frame: RectValue(x: 0, y: 0, width: 720, height: 640), isFocused: true)],
        contentWidth: 720,
        scrollOffset: 0,
        visibleSlotIDs: [slot.id],
        parkedSlotIDs: [],
        activeSlotIndex: 0
    )

    await environment.session.load(seedWorkspaces: [workspace])
    _ = environment.session.syncFocusedWindowMatch(
        workspaceID: workspace.id,
        slotID: slot.id,
        candidate: WindowCandidate(
            bundleID: "com.example.editor",
            appName: "Editor",
            windowTitle: "Project",
            processID: 101,
            windowID: 1,
            frame: .zero,
            isFocused: true,
            source: .accessibility
        ),
        matchConfidence: 1
    )

    environment.updateStageViewportFrame(CGRect(x: 100, y: 200, width: 1200, height: 720))
    await environment.applyChoreography(for: workspace, layout: layout)
    try await waitForMinimumApplyCount(1, service: choreographyService)

    #expect(choreographyService.applyCalls.last?.focusPolicy == .preserveExternalFocus)
}

@MainActor
@Test
func appEnvironmentReverseFocusPrefersSelectedWorkspaceForDuplicateSharedAppProcess() async throws {
    let registry = RecordingWindowRegistry(snapshot: WindowRegistrySnapshot(isAccessibilityTrusted: true))
    let choreographyService = RecordingChoreographyService()
    let store = makeWorkspaceStore("AppEnvironmentReverseFocusPreferredWorkspace")
    let environment = AppEnvironment(
        workspaceStore: store,
        windowRegistry: registry,
        adapterRegistry: AdapterRegistry(),
        diagnosticsCenter: DiagnosticsCenter(initialSnapshot: trustedDiagnosticsSnapshot()),
        choreographyService: choreographyService,
        registerDefaultAdapters: false
    )
    let apiZen = Slot(
        id: "api-zen",
        workspaceID: "api",
        kind: .externalWindow,
        label: "Zen",
        appBinding: AppBinding(bundleID: "app.zen-browser.zen"),
        widthPolicy: SizePolicy(mode: .fraction, value: 0.5),
        layoutRole: .secondary,
        runtimeBinding: RuntimeBinding(processID: 687, matchConfidence: 1, state: .attached)
    )
    let uiZen = Slot(
        id: "ui-zen",
        workspaceID: "ui",
        kind: .externalWindow,
        label: "Zen",
        appBinding: AppBinding(bundleID: "app.zen-browser.zen"),
        widthPolicy: SizePolicy(mode: .fraction, value: 0.5),
        layoutRole: .secondary,
        runtimeBinding: RuntimeBinding(processID: 687, matchConfidence: 1, state: .attached)
    )
    await environment.session.load(seedWorkspaces: [
        Workspace(id: "api", name: "API", activeSlotID: apiZen.id, slotOrder: [apiZen.id], layoutState: LayoutState(activeIndex: 0, centeredSlotID: apiZen.id), slots: [apiZen]),
        Workspace(id: "ui", name: "UI", activeSlotID: uiZen.id, slotOrder: [uiZen.id], layoutState: LayoutState(activeIndex: 0, centeredSlotID: uiZen.id), slots: [uiZen]),
    ])

    await environment.handleFocusedWindowCandidate(
        WindowCandidate(
            bundleID: "app.zen-browser.zen",
            appName: "Zen",
            windowTitle: "Docs",
            processID: 687,
            windowID: nil,
            frame: .zero,
            isFocused: true,
            source: .accessibility
        )
    )

    #expect(environment.session.selectedWorkspaceID == "api")
    #expect(environment.session.selectedWorkspace?.activeSlotID == "api-zen")
    #expect(environment.session.lastSelectionOrigin == .nativeFocusSync)
}

@MainActor
@Test
func appEnvironmentRefreshesRuntimeBindingsAfterChoreography() async throws {
    let registry = RecordingWindowRegistry(
        snapshot: WindowRegistrySnapshot(
            isAccessibilityTrusted: true,
            windows: [
                WindowCandidate(
                    bundleID: "com.example.browser",
                    appName: "Browser",
                    windowTitle: "Page",
                    processID: 202,
                    windowID: 7,
                    frame: .zero,
                    isFocused: true,
                    source: .accessibility
                ),
            ]
        )
    )
    let choreographyService = RecordingChoreographyService()
    let store = makeWorkspaceStore("AppEnvironmentRefreshBindings")
    let environment = AppEnvironment(
        workspaceStore: store,
        windowRegistry: registry,
        adapterRegistry: AdapterRegistry(),
        diagnosticsCenter: DiagnosticsCenter(initialSnapshot: trustedDiagnosticsSnapshot()),
        choreographyService: choreographyService,
        registerDefaultAdapters: false
    )
    let slot = Slot(
        id: "browser",
        workspaceID: "workspace",
        kind: .externalWindow,
        label: "Browser",
        appBinding: AppBinding(bundleID: "com.example.browser"),
        widthPolicy: SizePolicy(mode: .fraction, value: 1),
        layoutRole: .primary
    )
    let workspace = Workspace(
        id: "workspace",
        name: "Main",
        activeSlotID: slot.id,
        slotOrder: [slot.id],
        layoutState: LayoutState(activeIndex: 0, centeredSlotID: slot.id, visibleSlotIDs: [slot.id]),
        slots: [slot]
    )
    let layout = LayoutPlan(
        slotLayouts: [SlotLayout(slotID: slot.id, frame: RectValue(x: 0, y: 0, width: 720, height: 640), isFocused: true)],
        contentWidth: 720,
        scrollOffset: 0,
        visibleSlotIDs: [slot.id],
        parkedSlotIDs: [],
        activeSlotIndex: 0
    )

    await environment.session.load(seedWorkspaces: [workspace])
    environment.updateStageViewportFrame(CGRect(x: 100, y: 200, width: 1200, height: 720))
    await environment.applyChoreography(for: workspace, layout: layout)
    try await waitForMinimumApplyCount(1, service: choreographyService)
    try await waitForRuntimeBinding(processID: 202, windowID: 7, in: environment.session, slotID: "browser")

    #expect(environment.session.selectedWorkspace?.slots.first?.runtimeBinding?.processID == 202)
    #expect(environment.session.selectedWorkspace?.slots.first?.runtimeBinding?.windowID == 7)
}

@MainActor
@Test
func appEnvironmentFocusedWindowSyncSwitchesWorkspaceWhenMatched() async throws {
    let registry = RecordingWindowRegistry(snapshot: WindowRegistrySnapshot(isAccessibilityTrusted: true))
    let store = makeWorkspaceStore("AppEnvironmentFocusedWorkspaceSwitch")
    let environment = AppEnvironment(
        workspaceStore: store,
        windowRegistry: registry,
        adapterRegistry: AdapterRegistry(),
        diagnosticsCenter: DiagnosticsCenter(initialSnapshot: trustedDiagnosticsSnapshot()),
        registerDefaultAdapters: false
    )
    let apiSlot = Slot(
        id: "editor",
        workspaceID: "api",
        kind: .externalWindow,
        label: "Editor",
        appBinding: AppBinding(bundleID: "com.example.editor"),
        widthPolicy: SizePolicy(mode: .fraction, value: 1),
        layoutRole: .primary,
        runtimeBinding: RuntimeBinding(processID: 101, windowID: 1, matchConfidence: 1)
    )
    let uiSlot = Slot(
        id: "browser",
        workspaceID: "ui",
        kind: .externalWindow,
        label: "Browser",
        appBinding: AppBinding(bundleID: "com.example.browser"),
        widthPolicy: SizePolicy(mode: .fraction, value: 1),
        layoutRole: .primary
    )
    await environment.session.load(seedWorkspaces: [
        Workspace(id: "api", name: "API", activeSlotID: apiSlot.id, slotOrder: [apiSlot.id], layoutState: LayoutState(activeIndex: 0, centeredSlotID: apiSlot.id, visibleSlotIDs: [apiSlot.id]), slots: [apiSlot]),
        Workspace(id: "ui", name: "UI", activeSlotID: uiSlot.id, slotOrder: [uiSlot.id], layoutState: LayoutState(activeIndex: 0, centeredSlotID: uiSlot.id, visibleSlotIDs: [uiSlot.id]), slots: [uiSlot]),
    ])

    await environment.handleFocusedWindowCandidate(
        WindowCandidate(
            bundleID: "com.example.browser",
            appName: "Browser",
            windowTitle: "Anything",
            processID: 202,
            windowID: 7,
            frame: .zero,
            isFocused: true,
            source: .accessibility
        )
    )

    #expect(environment.session.selectedWorkspaceID == "ui")
    #expect(environment.session.selectedWorkspace?.activeSlotID == "browser")
    #expect(environment.session.lastSelectionOrigin == .nativeFocusSync)
}

@MainActor
@Test
func appEnvironmentIgnoresUnmatchedFocusedWindows() async throws {
    let registry = RecordingWindowRegistry(snapshot: WindowRegistrySnapshot(isAccessibilityTrusted: true))
    let store = makeWorkspaceStore("AppEnvironmentIgnoreUnmatched")
    let environment = AppEnvironment(
        workspaceStore: store,
        windowRegistry: registry,
        adapterRegistry: AdapterRegistry(),
        diagnosticsCenter: DiagnosticsCenter(initialSnapshot: trustedDiagnosticsSnapshot()),
        registerDefaultAdapters: false
    )
    let slot = Slot(
        id: "editor",
        workspaceID: "workspace",
        kind: .externalWindow,
        label: "Editor",
        appBinding: AppBinding(bundleID: "com.example.editor"),
        widthPolicy: SizePolicy(mode: .fraction, value: 1),
        layoutRole: .primary
    )
    await environment.session.load(seedWorkspaces: [
        Workspace(id: "workspace", name: "Main", activeSlotID: slot.id, slotOrder: [slot.id], layoutState: LayoutState(activeIndex: 0, centeredSlotID: slot.id, visibleSlotIDs: [slot.id]), slots: [slot]),
    ])

    await environment.handleFocusedWindowCandidate(
        WindowCandidate(
            bundleID: "com.example.other",
            appName: "Other",
            windowTitle: "Elsewhere",
            processID: 303,
            windowID: 9,
            frame: .zero,
            isFocused: true,
            source: .accessibility
        )
    )

    #expect(environment.session.selectedWorkspaceID == "workspace")
    #expect(environment.session.selectedWorkspace?.activeSlotID == "editor")
    #expect(environment.session.lastSelectionOrigin == .nexusNavigation)
}

@MainActor
@Test
func appEnvironmentSuppressesImmediateReverseFocusEchoAfterNexusNavigation() async throws {
    let registry = RecordingWindowRegistry(snapshot: WindowRegistrySnapshot(isAccessibilityTrusted: true))
    let choreographyService = RecordingChoreographyService()
    let store = makeWorkspaceStore("AppEnvironmentFocusEcho")
    let environment = AppEnvironment(
        workspaceStore: store,
        windowRegistry: registry,
        adapterRegistry: AdapterRegistry(),
        diagnosticsCenter: DiagnosticsCenter(initialSnapshot: trustedDiagnosticsSnapshot()),
        choreographyService: choreographyService,
        registerDefaultAdapters: false
    )
    let slot = Slot(
        id: "editor",
        workspaceID: "workspace",
        kind: .externalWindow,
        label: "Editor",
        appBinding: AppBinding(bundleID: "com.example.editor"),
        widthPolicy: SizePolicy(mode: .fraction, value: 1),
        layoutRole: .primary,
        runtimeBinding: RuntimeBinding(processID: 101, windowID: 1, matchConfidence: 1)
    )
    let workspace = Workspace(
        id: "workspace",
        name: "Main",
        activeSlotID: slot.id,
        slotOrder: [slot.id],
        layoutState: LayoutState(activeIndex: 0, centeredSlotID: slot.id, visibleSlotIDs: [slot.id]),
        slots: [slot]
    )
    let layout = LayoutPlan(
        slotLayouts: [SlotLayout(slotID: slot.id, frame: RectValue(x: 0, y: 0, width: 720, height: 640), isFocused: true)],
        contentWidth: 720,
        scrollOffset: 0,
        visibleSlotIDs: [slot.id],
        parkedSlotIDs: [],
        activeSlotIndex: 0
    )

    await environment.session.load(seedWorkspaces: [workspace])
    environment.updateStageViewportFrame(CGRect(x: 100, y: 200, width: 1200, height: 720))
    await environment.applyChoreography(for: workspace, layout: layout)
    try await waitForMinimumApplyCount(1, service: choreographyService)

    await environment.handleFocusedWindowCandidate(
        WindowCandidate(
            bundleID: "com.example.editor",
            appName: "Editor",
            windowTitle: "Project",
            processID: 101,
            windowID: 1,
            frame: .zero,
            isFocused: true,
            source: .accessibility
        )
    )

    #expect(environment.session.lastSelectionOrigin == .nexusNavigation)
}

@MainActor
@Test
func appEnvironmentSetsBlockedStatusWhenChoreographyIsDenied() async throws {
    let registry = RecordingWindowRegistry(snapshot: WindowRegistrySnapshot(isAccessibilityTrusted: false))
    let choreographyService = RecordingChoreographyService()
    choreographyService.outcome = .blocked(.accessibilityDenied)
    let store = makeWorkspaceStore("AppEnvironmentBlockedStatus")
    let environment = AppEnvironment(
        workspaceStore: store,
        windowRegistry: registry,
        adapterRegistry: AdapterRegistry(),
        diagnosticsCenter: DiagnosticsCenter(initialSnapshot: trustedDiagnosticsSnapshot()),
        choreographyService: choreographyService,
        registerDefaultAdapters: false
    )
    let slot = Slot(
        id: "editor",
        workspaceID: "workspace",
        kind: .externalWindow,
        label: "Editor",
        appBinding: AppBinding(bundleID: "com.example.editor"),
        widthPolicy: SizePolicy(mode: .fraction, value: 1),
        layoutRole: .primary
    )
    let workspace = Workspace(
        id: "workspace",
        name: "Main",
        activeSlotID: slot.id,
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

    environment.updateStageViewportFrame(CGRect(x: 100, y: 200, width: 1200, height: 720))
    await environment.applyChoreography(for: workspace, layout: layout)
    try await waitForMinimumApplyCount(1, service: choreographyService)
    try await waitForStatusContaining("blocked", in: environment.session)

    #expect(environment.session.statusMessage.localizedCaseInsensitiveContains("blocked"))
    #expect(environment.session.statusMessage.localizedCaseInsensitiveContains("Focused") == false)
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

@MainActor
private func waitForMinimumApplyCount(_ minimumCount: Int, service: RecordingChoreographyService) async throws {
    for _ in 0..<50 {
        if service.applyCalls.count >= minimumCount {
            return
        }
        await Task.yield()
        try await Task.sleep(nanoseconds: 10_000_000)
    }

    Issue.record("Timed out waiting for at least \(minimumCount) choreography apply call(s); saw \(service.applyCalls.count).")
    throw TestFailure()
}

@MainActor
private func waitForStatusContaining(_ fragment: String, in session: WorkspaceSession) async throws {
    for _ in 0..<50 {
        if session.statusMessage.localizedCaseInsensitiveContains(fragment) {
            return
        }
        await Task.yield()
        try await Task.sleep(nanoseconds: 10_000_000)
    }

    Issue.record("Timed out waiting for status containing '\(fragment)'; saw '\(session.statusMessage)'.")
    throw TestFailure()
}

@MainActor
private func waitForRuntimeBinding(
    processID: Int,
    windowID: Int?,
    in session: WorkspaceSession,
    slotID: String
) async throws {
    for _ in 0..<50 {
        if let binding = session.selectedWorkspace?.slots.first(where: { $0.id == slotID })?.runtimeBinding,
           binding.processID == processID,
           binding.windowID == windowID {
            return
        }
        await Task.yield()
        try await Task.sleep(nanoseconds: 10_000_000)
    }

    Issue.record("Timed out waiting for runtime binding \(processID)/\(windowID.map(String.init) ?? "nil") on slot \(slotID).")
    throw TestFailure()
}

private func trustedDiagnosticsSnapshot() -> DiagnosticsSnapshot {
    DiagnosticsSnapshot(
        permissions: [
            PermissionStatus(
                kind: .accessibility,
                state: .granted,
                detail: "Accessibility access is enabled for the running Nexus.app."
            ),
        ]
    )
}

private func makeWorkspaceStore(_ label: String) -> JSONWorkspaceStore {
    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
    return JSONWorkspaceStore(baseDirectoryURL: tempURL)
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
    var focusedCandidate: WindowCandidate?
    private(set) var operations: [Operation] = []

    init(snapshot: WindowRegistrySnapshot) {
        self.snapshotValue = snapshot
    }

    func snapshot() async throws -> WindowRegistrySnapshot {
        snapshotValue
    }

    func focusedWindowCandidate() async throws -> WindowCandidate? {
        focusedCandidate
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

private final class RecordingAdapter: @unchecked Sendable, NexusAdapter {
    let id: String
    let supportedBundleIDs: [String]

    private(set) var stagedSlotIDs: [String] = []
    private(set) var parkedSlotIDs: [String] = []
    private(set) var activatedSlotIDs: [String] = []

    init(id: String, supportedBundleIDs: [String]) {
        self.id = id
        self.supportedBundleIDs = supportedBundleIDs
    }

    func discover(in snapshot: WindowRegistrySnapshot) async -> [WindowCandidate] {
        snapshot.windows.filter { supportedBundleIDs.contains($0.bundleID ?? "") }
    }

    func activate(slot: Slot) async throws {
        activatedSlotIDs.append(slot.id)
    }

    func stage(slot: Slot, action: VisibilityAction) async throws {
        _ = action
        stagedSlotIDs.append(slot.id)
    }

    func park(slot: Slot) async throws {
        parkedSlotIDs.append(slot.id)
    }

    func captureState(for slot: Slot) async throws -> AdapterState? {
        _ = slot
        return nil
    }

    func restoreState(for slot: Slot, state: AdapterState?) async throws -> RuntimeBinding? {
        _ = slot
        _ = state
        return nil
    }

    func openTarget(for slot: Slot) async throws {
        _ = slot
    }

    func healthCheck() async -> AdapterHealthReport {
        AdapterHealthReport(adapterID: id, health: .healthy, detail: "ok")
    }

    func serializeState(_ state: AdapterState) throws -> Data {
        try JSONEncoder().encode(state)
    }
}

@MainActor
private final class RecordingChoreographyService: WindowChoreographing {
    struct ApplyCall: Equatable {
        let workspaceID: String
        let frame: CGRect?
        let focusPolicy: ChoreographyFocusPolicy
    }

    var outcome: ChoreographyOutcome = .applied
    private(set) var applyCalls: [ApplyCall] = []

    func apply(
        workspace: Workspace,
        previousWorkspace: Workspace?,
        layout: LayoutPlan,
        stageViewportFrame: CGRect?,
        focusPolicy: ChoreographyFocusPolicy
    ) async -> ChoreographyOutcome {
        _ = previousWorkspace
        _ = layout
        applyCalls.append(ApplyCall(workspaceID: workspace.id, frame: stageViewportFrame?.integral, focusPolicy: focusPolicy))
        return outcome
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

@MainActor
private final class RecordingStageMaskCoordinator: StageMaskCoordinating {
    struct UpdateCall: Equatable {
        let occlusionBands: [RectValue]
        let frame: CGRect?
    }

    private(set) var updateCalls: [UpdateCall] = []
    private(set) var hideAllCount = 0
    private(set) var attachedWindowWasSet = false

    func attach(to window: NSWindow?) {
        attachedWindowWasSet = attachedWindowWasSet || window != nil
    }

    func update(layout: LayoutPlan?, stageViewportFrame: CGRect?) {
        updateCalls.append(
            UpdateCall(
                occlusionBands: layout?.occlusionBands ?? [],
                frame: stageViewportFrame?.integral
            )
        )
    }

    func hideAll() {
        hideAllCount += 1
    }
}

private struct TestFailure: Error {}
