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
