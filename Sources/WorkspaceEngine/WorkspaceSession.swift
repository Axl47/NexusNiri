import Foundation
import Observation
import SharedTypes

@MainActor
@Observable
public final class WorkspaceSession {
    public private(set) var workspaces: [Workspace] = []
    public private(set) var selectedWorkspaceID: String?
    public private(set) var recentWorkspaceIDs: [String] = []
    public private(set) var adapterStates: [AdapterState] = []
    public private(set) var snapshots: [SessionSnapshot] = []
    public var statusMessage: String = "Bootstrapping Nexus..."

    @ObservationIgnored
    private let store: WorkspaceStore

    public init(store: WorkspaceStore) {
        self.store = store
    }

    public var selectedWorkspace: Workspace? {
        workspaces.first { $0.id == selectedWorkspaceID } ?? workspaces.first
    }

    public var selectedSlotIndex: Int {
        guard let workspace = selectedWorkspace else { return 0 }
        return max(0, workspace.slotOrder.firstIndex(of: workspace.activeSlotID ?? "") ?? workspace.layoutState.activeIndex)
    }

    public func load(seedWorkspaces: [Workspace]) async {
        do {
            let loaded = try await store.loadState()
            if loaded.workspaces.isEmpty {
                let seeded = PersistedWorkspaceState(
                    workspaces: seedWorkspaces,
                    selectedWorkspaceID: seedWorkspaces.first?.id,
                    recentWorkspaceIDs: seedWorkspaces.map(\.id),
                    adapterStates: [],
                    snapshots: []
                )
                apply(seeded)
                try await store.saveState(currentPersistedState())
                statusMessage = "Seeded default workspaces."
            } else {
                apply(loaded)
                statusMessage = "Loaded \(loaded.workspaces.count) workspace(s)."
            }
        } catch {
            workspaces = seedWorkspaces
            selectedWorkspaceID = seedWorkspaces.first?.id
            recentWorkspaceIDs = seedWorkspaces.map(\.id)
            statusMessage = "Fell back to bundled defaults: \(error.localizedDescription)"
        }
    }

    public func refreshStatus(_ message: String) {
        statusMessage = message
    }

    public func addWorkspace(named name: String? = nil) {
        let index = workspaces.count + 1
        let workspaceName = (name?.isEmpty == false ? name : nil) ?? "Workspace \(index)"
        let workspaceID = UUID().uuidString
        let now = Date()

        let slots = [
            Slot(
                workspaceID: workspaceID,
                kind: .externalWindow,
                label: "Editor",
                appBinding: AppBinding(bundleID: "com.microsoft.VSCode"),
                widthPolicy: SizePolicy(mode: .fraction, value: 0.55, minimum: 540),
                layoutRole: .primary,
                warmPreference: .hot
            ),
            Slot(
                workspaceID: workspaceID,
                kind: .externalWindow,
                label: "Zen",
                appBinding: AppBinding(bundleID: "app.zen-browser.zen"),
                widthPolicy: SizePolicy(mode: .fraction, value: 0.45, minimum: 500),
                layoutRole: .secondary,
                warmPreference: .warm
            ),
            Slot(
                workspaceID: workspaceID,
                kind: .hybrid,
                label: "Tether",
                appBinding: AppBinding(
                    bundleID: "dev.tether.desktop",
                    adapterHints: ["baseURL": "http://127.0.0.1:3773", "wsURL": "ws://127.0.0.1:3773"]
                ),
                widthPolicy: SizePolicy(mode: .fraction, value: 0.40, minimum: 460),
                layoutRole: .support,
                adapterID: "tether",
                warmPreference: .hot
            ),
        ]

        let slotOrder = slots.map(\.id)
        let workspace = Workspace(
            id: workspaceID,
            name: workspaceName,
            description: "User-created workspace",
            activeSlotID: slotOrder.first,
            slotOrder: slotOrder,
            layoutState: LayoutState(activeIndex: 0, centeredSlotID: slotOrder.first, visibleSlotIDs: slotOrder.prefix(2).map { $0 }),
            createdAt: now,
            updatedAt: now,
            slots: slots
        )

        workspaces.append(workspace)
        selectedWorkspaceID = workspace.id
        appendRecent(workspace.id)
        statusMessage = "Added \(workspace.name)."
        persistSoon()
    }

    public func removeSelectedWorkspace() {
        guard let selectedWorkspaceID else { return }
        workspaces.removeAll { $0.id == selectedWorkspaceID }

        let fallback = workspaces.first?.id
        self.selectedWorkspaceID = fallback
        if let fallback {
            appendRecent(fallback)
        }

        statusMessage = workspaces.isEmpty ? "Removed the last workspace." : "Removed workspace."
        persistSoon()
    }

    public func renameSelectedWorkspace(to name: String) {
        guard let selectedWorkspaceID, let index = workspaces.firstIndex(where: { $0.id == selectedWorkspaceID }) else { return }
        workspaces[index].name = name
        workspaces[index].updatedAt = .now
        statusMessage = "Renamed workspace to \(name)."
        persistSoon()
    }

    public func selectWorkspace(id: String) {
        guard workspaces.contains(where: { $0.id == id }) else { return }
        selectedWorkspaceID = id
        appendRecent(id)
        statusMessage = "Switched workspace."
        persistSoon()
    }

    public func selectWorkspace(at index: Int) {
        guard workspaces.indices.contains(index) else { return }
        selectWorkspace(id: workspaces[index].id)
    }

    public func selectNextWorkspace() {
        guard let selectedWorkspaceID,
              let index = workspaces.firstIndex(where: { $0.id == selectedWorkspaceID }),
              !workspaces.isEmpty else { return }

        let nextIndex = (index + 1) % workspaces.count
        selectWorkspace(id: workspaces[nextIndex].id)
    }

    public func selectPreviousWorkspace() {
        guard let selectedWorkspaceID,
              let index = workspaces.firstIndex(where: { $0.id == selectedWorkspaceID }),
              !workspaces.isEmpty else { return }

        let previousIndex = (index - 1 + workspaces.count) % workspaces.count
        selectWorkspace(id: workspaces[previousIndex].id)
    }

    public func selectSlot(id: String) {
        guard let workspaceIndex = selectedWorkspace.flatMap({ workspace in
            workspaces.firstIndex(where: { $0.id == workspace.id })
        }) else {
            return
        }

        guard workspaces[workspaceIndex].slotOrder.contains(id) else { return }
        let slotIndex = workspaces[workspaceIndex].slotOrder.firstIndex(of: id) ?? 0
        workspaces[workspaceIndex].activeSlotID = id
        workspaces[workspaceIndex].layoutState.activeIndex = slotIndex
        workspaces[workspaceIndex].layoutState.centeredSlotID = id
        workspaces[workspaceIndex].updatedAt = .now
        statusMessage = "Focused slot."
        persistSoon()
    }

    public func selectNextSlot() {
        guard let workspace = selectedWorkspace, !workspace.slotOrder.isEmpty else { return }
        let currentIndex = workspace.slotOrder.firstIndex(of: workspace.activeSlotID ?? "") ?? 0
        let nextIndex = min(workspace.slotOrder.count - 1, currentIndex + 1)
        selectSlot(id: workspace.slotOrder[nextIndex])
    }

    public func selectPreviousSlot() {
        guard let workspace = selectedWorkspace, !workspace.slotOrder.isEmpty else { return }
        let currentIndex = workspace.slotOrder.firstIndex(of: workspace.activeSlotID ?? "") ?? 0
        let previousIndex = max(0, currentIndex - 1)
        selectSlot(id: workspace.slotOrder[previousIndex])
    }

    public func updateVisibility(using layout: LayoutPlan) {
        guard let workspaceID = selectedWorkspaceID,
              let index = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
            return
        }

        workspaces[index].layoutState.visibleSlotIDs = layout.visibleSlotIDs
        workspaces[index].layoutState.parkedSlotIDs = layout.parkedSlotIDs
        workspaces[index].layoutState.scrollAnchor = layout.scrollOffset
        workspaces[index].layoutState.activeIndex = layout.activeSlotIndex
        workspaces[index].layoutState.centeredSlotID = workspaces[index].slotOrder[safe: layout.activeSlotIndex]
        persistSoon()
    }

    public func currentPersistedState() -> PersistedWorkspaceState {
        PersistedWorkspaceState(
            workspaces: workspaces,
            selectedWorkspaceID: selectedWorkspaceID,
            recentWorkspaceIDs: recentWorkspaceIDs,
            adapterStates: adapterStates,
            snapshots: snapshots,
            updatedAt: .now
        )
    }

    private func apply(_ state: PersistedWorkspaceState) {
        workspaces = state.workspaces
        selectedWorkspaceID = state.selectedWorkspaceID ?? state.workspaces.first?.id
        recentWorkspaceIDs = state.recentWorkspaceIDs
        adapterStates = state.adapterStates
        snapshots = state.snapshots
    }

    private func appendRecent(_ workspaceID: String) {
        recentWorkspaceIDs.removeAll { $0 == workspaceID }
        recentWorkspaceIDs.insert(workspaceID, at: 0)
        recentWorkspaceIDs = Array(recentWorkspaceIDs.prefix(12))
    }

    private func persistSoon() {
        let state = currentPersistedState()
        Task {
            try? await store.saveState(state)
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
