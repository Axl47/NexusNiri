import Foundation
import Testing
import SharedTypes
@testable import WorkspaceEngine

@Test
func jsonWorkspaceStoreRoundTripsState() async throws {
    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("NexusWorkspaceStoreTests-\(UUID().uuidString)", isDirectory: true)
    let store = JSONWorkspaceStore(baseDirectoryURL: tempURL)
    let state = PersistedWorkspaceState(
        workspaces: [
            Workspace(name: "API", slots: []),
        ],
        selectedWorkspaceID: "selected"
    )

    try await store.saveState(state)
    let loaded = try await store.loadState()

    #expect(loaded.workspaces.count == 1)
    #expect(loaded.selectedWorkspaceID == "selected")
}

@MainActor
@Test
func workspaceSessionSeedsDefaultsAndAddsWorkspace() async {
    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("NexusWorkspaceSessionTests-\(UUID().uuidString)", isDirectory: true)
    let store = JSONWorkspaceStore(baseDirectoryURL: tempURL)
    let session = WorkspaceSession(store: store)
    let seed = Workspace(name: "Seed", slots: [])

    await session.load(seedWorkspaces: [seed])
    session.addWorkspace(named: "Fresh")

    #expect(session.workspaces.count == 2)
    #expect(session.selectedWorkspace?.name == "Fresh")
}

@MainActor
@Test
func workspaceSessionResizesSelectedSlotWidthPolicy() async {
    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("NexusWorkspaceResizeTests-\(UUID().uuidString)", isDirectory: true)
    let store = JSONWorkspaceStore(baseDirectoryURL: tempURL)
    let slot = Slot(
        id: "editor",
        workspaceID: "workspace",
        kind: .externalWindow,
        label: "Editor",
        widthPolicy: SizePolicy(mode: .fraction, value: 0.5, minimum: 320),
        layoutRole: .primary
    )
    let workspace = Workspace(
        id: "workspace",
        name: "Resize",
        activeSlotID: "editor",
        slotOrder: ["editor"],
        slots: [slot]
    )
    let session = WorkspaceSession(store: store)

    await session.load(seedWorkspaces: [workspace])
    session.resizeSlot(id: "editor", to: 840, viewportWidth: 1200, persist: false)

    let resizedSlot = session.selectedWorkspace?.slots.first
    #expect(resizedSlot?.widthPolicy.mode == .fraction)
    #expect(resizedSlot?.widthPolicy.value == 0.7)
}

@MainActor
@Test
func workspaceSessionSelectsNeighborSlotsDeterministically() async {
    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("NexusWorkspaceNavigationTests-\(UUID().uuidString)", isDirectory: true)
    let store = JSONWorkspaceStore(baseDirectoryURL: tempURL)
    let slots = [
        Slot(id: "editor", workspaceID: "workspace", kind: .externalWindow, label: "Editor", widthPolicy: SizePolicy(mode: .fraction, value: 0.55), layoutRole: .primary),
        Slot(id: "browser", workspaceID: "workspace", kind: .externalWindow, label: "Browser", widthPolicy: SizePolicy(mode: .fraction, value: 0.45), layoutRole: .secondary),
        Slot(id: "tether", workspaceID: "workspace", kind: .hybrid, label: "Tether", widthPolicy: SizePolicy(mode: .fraction, value: 0.4), layoutRole: .support),
    ]
    let workspace = Workspace(
        id: "workspace",
        name: "API",
        activeSlotID: "editor",
        slotOrder: slots.map(\.id),
        layoutState: LayoutState(activeIndex: 0, centeredSlotID: "editor"),
        slots: slots
    )
    let session = WorkspaceSession(store: store)

    await session.load(seedWorkspaces: [workspace])
    session.selectNextSlot()
    #expect(session.selectedWorkspace?.activeSlotID == "browser")
    #expect(session.selectedWorkspace?.layoutState.activeIndex == 1)

    session.selectPreviousSlot()
    #expect(session.selectedWorkspace?.activeSlotID == "editor")
    #expect(session.selectedWorkspace?.layoutState.activeIndex == 0)
}

@MainActor
@Test
func workspaceSessionPreservesPerWorkspaceActiveSlotState() async {
    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("NexusWorkspaceSwitchTests-\(UUID().uuidString)", isDirectory: true)
    let store = JSONWorkspaceStore(baseDirectoryURL: tempURL)

    let apiSlots = [
        Slot(id: "editor", workspaceID: "api", kind: .externalWindow, label: "Editor", widthPolicy: SizePolicy(mode: .fraction, value: 0.55), layoutRole: .primary),
        Slot(id: "browser", workspaceID: "api", kind: .externalWindow, label: "Browser", widthPolicy: SizePolicy(mode: .fraction, value: 0.45), layoutRole: .secondary),
    ]
    let uiSlots = [
        Slot(id: "zed", workspaceID: "ui", kind: .externalWindow, label: "Zed", widthPolicy: SizePolicy(mode: .fraction, value: 0.55), layoutRole: .primary),
        Slot(id: "zen", workspaceID: "ui", kind: .externalWindow, label: "Zen", widthPolicy: SizePolicy(mode: .fraction, value: 0.45), layoutRole: .secondary),
    ]

    let workspaces = [
        Workspace(
            id: "api",
            name: "API",
            activeSlotID: "editor",
            slotOrder: apiSlots.map(\.id),
            layoutState: LayoutState(activeIndex: 0, centeredSlotID: "editor"),
            slots: apiSlots
        ),
        Workspace(
            id: "ui",
            name: "UI",
            activeSlotID: "zed",
            slotOrder: uiSlots.map(\.id),
            layoutState: LayoutState(activeIndex: 0, centeredSlotID: "zed"),
            slots: uiSlots
        ),
    ]

    let session = WorkspaceSession(store: store)
    await session.load(seedWorkspaces: workspaces)

    session.selectSlot(id: "browser")
    session.selectWorkspace(id: "ui")
    session.selectSlot(id: "zen")
    session.selectWorkspace(id: "api")

    #expect(session.selectedWorkspace?.activeSlotID == "browser")
    #expect(session.workspaces.first(where: { $0.id == "ui" })?.activeSlotID == "zen")
}

@MainActor
@Test
func workspaceSessionSyncFocusedWindowMatchSwitchesWorkspaceAndUpdatesBinding() async {
    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("NexusWorkspaceFocusSyncTests-\(UUID().uuidString)", isDirectory: true)
    let store = JSONWorkspaceStore(baseDirectoryURL: tempURL)
    let apiSlot = Slot(
        id: "editor",
        workspaceID: "api",
        kind: .externalWindow,
        label: "Editor",
        appBinding: AppBinding(bundleID: "com.example.editor"),
        widthPolicy: SizePolicy(mode: .fraction, value: 0.55),
        layoutRole: .primary
    )
    let uiSlot = Slot(
        id: "browser",
        workspaceID: "ui",
        kind: .externalWindow,
        label: "Browser",
        appBinding: AppBinding(bundleID: "com.example.browser"),
        widthPolicy: SizePolicy(mode: .fraction, value: 0.45),
        layoutRole: .primary
    )
    let session = WorkspaceSession(store: store)
    await session.load(seedWorkspaces: [
        Workspace(id: "api", name: "API", activeSlotID: apiSlot.id, slotOrder: [apiSlot.id], layoutState: LayoutState(activeIndex: 0, centeredSlotID: apiSlot.id), slots: [apiSlot]),
        Workspace(id: "ui", name: "UI", activeSlotID: uiSlot.id, slotOrder: [uiSlot.id], layoutState: LayoutState(activeIndex: 0, centeredSlotID: uiSlot.id), slots: [uiSlot]),
    ])

    let changed = session.syncFocusedWindowMatch(
        workspaceID: "ui",
        slotID: "browser",
        candidate: WindowCandidate(
            bundleID: "com.example.browser",
            appName: "Browser",
            windowTitle: "Docs",
            processID: 202,
            windowID: 7,
            frame: .zero,
            isFocused: true,
            source: .accessibility
        ),
        matchConfidence: 0.9
    )

    #expect(changed)
    #expect(session.selectedWorkspaceID == "ui")
    #expect(session.selectedWorkspace?.activeSlotID == "browser")
    #expect(session.selectedWorkspace?.layoutState.centeredSlotID == "browser")
    #expect(session.lastSelectionOrigin == .nativeFocusSync)
    #expect(session.selectedWorkspace?.slots.first?.runtimeBinding?.processID == 202)
    #expect(session.selectedWorkspace?.slots.first?.runtimeBinding?.windowID == 7)
    #expect(session.selectedWorkspace?.slots.first?.runtimeBinding?.state == .attached)
}

@MainActor
@Test
func workspaceSessionSyncFocusedWindowMatchNoOpsWhenSelectionAndBindingAreCurrent() async {
    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("NexusWorkspaceFocusSyncNoOpTests-\(UUID().uuidString)", isDirectory: true)
    let store = JSONWorkspaceStore(baseDirectoryURL: tempURL)
    let slot = Slot(
        id: "editor",
        workspaceID: "workspace",
        kind: .externalWindow,
        label: "Editor",
        appBinding: AppBinding(bundleID: "com.example.editor"),
        widthPolicy: SizePolicy(mode: .fraction, value: 1),
        layoutRole: .primary,
        runtimeBinding: RuntimeBinding(processID: 101, windowID: 1, matchConfidence: 1, state: .attached)
    )
    let session = WorkspaceSession(store: store)
    await session.load(seedWorkspaces: [
        Workspace(id: "workspace", name: "Main", activeSlotID: slot.id, slotOrder: [slot.id], layoutState: LayoutState(activeIndex: 0, centeredSlotID: slot.id), slots: [slot]),
    ])

    let firstChange = session.syncFocusedWindowMatch(
        workspaceID: "workspace",
        slotID: "editor",
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
    let secondChange = session.syncFocusedWindowMatch(
        workspaceID: "workspace",
        slotID: "editor",
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

    #expect(firstChange == false)
    #expect(secondChange == false)
    #expect(session.lastSelectionOrigin == .nexusNavigation)
}

@MainActor
@Test
func workspaceSessionRefreshRuntimeBindingUpdatesWithoutChangingSelectionOrigin() async {
    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("NexusWorkspaceRefreshBindingTests-\(UUID().uuidString)", isDirectory: true)
    let store = JSONWorkspaceStore(baseDirectoryURL: tempURL)
    let slot = Slot(
        id: "editor",
        workspaceID: "workspace",
        kind: .externalWindow,
        label: "Editor",
        appBinding: AppBinding(bundleID: "com.example.editor"),
        widthPolicy: SizePolicy(mode: .fraction, value: 1),
        layoutRole: .primary
    )
    let session = WorkspaceSession(store: store)
    await session.load(seedWorkspaces: [
        Workspace(id: "workspace", name: "Main", activeSlotID: slot.id, slotOrder: [slot.id], layoutState: LayoutState(activeIndex: 0, centeredSlotID: slot.id), slots: [slot]),
    ])

    let changed = session.refreshRuntimeBinding(
        workspaceID: "workspace",
        slotID: "editor",
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
        matchConfidence: 0.7
    )

    #expect(changed)
    #expect(session.lastSelectionOrigin == .nexusNavigation)
    #expect(session.selectedWorkspace?.slots.first?.runtimeBinding?.processID == 101)
    #expect(session.selectedWorkspace?.slots.first?.runtimeBinding?.windowID == 1)
}
