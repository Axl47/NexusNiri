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
