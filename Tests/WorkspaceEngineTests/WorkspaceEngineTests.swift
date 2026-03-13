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
