import Foundation
import Observation
import SharedTypes

public enum SelectionOrigin: Sendable {
    case nexusNavigation
    case nativeFocusSync
    case nativeGeometrySync
}

@MainActor
@Observable
public final class WorkspaceSession {
    public private(set) var workspaces: [Workspace] = []
    public private(set) var selectedWorkspaceID: String?
    public private(set) var recentWorkspaceIDs: [String] = []
    public private(set) var adapterStates: [AdapterState] = []
    public private(set) var snapshots: [SessionSnapshot] = []
    public var statusMessage: String = "Bootstrapping Nexus..."
    @ObservationIgnored public private(set) var lastSelectionOrigin: SelectionOrigin = .nexusNavigation

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
            let loaded = normalizeLegacyBundleIDs(in: try await store.loadState())
            if loaded.workspaces.isEmpty {
                let seeded = PersistedWorkspaceState(
                    workspaces: normalizeLegacyBundleIDs(in: seedWorkspaces),
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
                    bundleID: "com.t3tools.tether",
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
        selectWorkspace(id: id, origin: .nexusNavigation)
    }

    public func selectWorkspace(id: String, origin: SelectionOrigin) {
        guard workspaces.contains(where: { $0.id == id }) else { return }
        lastSelectionOrigin = origin

        let wasSelected = selectedWorkspaceID == id
        selectedWorkspaceID = id
        appendRecent(id)
        guard wasSelected == false else { return }

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
        selectSlot(id: id, origin: .nexusNavigation)
    }

    public func selectSlot(id: String, origin: SelectionOrigin) {
        guard let workspaceIndex = selectedWorkspace.flatMap({ workspace in
            workspaces.firstIndex(where: { $0.id == workspace.id })
        }) else {
            return
        }

        guard workspaces[workspaceIndex].slotOrder.contains(id) else { return }
        let slotIndex = workspaces[workspaceIndex].slotOrder.firstIndex(of: id) ?? 0
        let didChangeSelection =
            workspaces[workspaceIndex].activeSlotID != id ||
            workspaces[workspaceIndex].layoutState.activeIndex != slotIndex ||
            workspaces[workspaceIndex].layoutState.centeredSlotID != id

        lastSelectionOrigin = origin
        workspaces[workspaceIndex].activeSlotID = id
        workspaces[workspaceIndex].layoutState.activeIndex = slotIndex
        workspaces[workspaceIndex].layoutState.centeredSlotID = id
        guard didChangeSelection else { return }

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

    public func resizeSlot(
        id: String,
        to width: Double,
        viewportWidth: Double,
        persist: Bool = true
    ) {
        guard viewportWidth > 0,
              let workspaceIndex = selectedWorkspace.flatMap({ workspace in
                  workspaces.firstIndex(where: { $0.id == workspace.id })
              }),
              let slotIndex = workspaces[workspaceIndex].slots.firstIndex(where: { $0.id == id }) else {
            return
        }

        _ = applySlotWidth(
            workspaceIndex: workspaceIndex,
            slotIndex: slotIndex,
            observedWidth: width,
            viewportWidth: viewportWidth,
            persist: persist,
            originOnChange: nil,
            statusMessageOnPersist: "Resized slot."
        )
    }

    @discardableResult
    public func refreshSlotWidth(
        workspaceID: String,
        slotID: String,
        observedWidth: Double,
        viewportWidth: Double,
        persist: Bool = true
    ) -> Bool {
        guard viewportWidth > 0,
              let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }),
              let slotIndex = workspaces[workspaceIndex].slots.firstIndex(where: { $0.id == slotID }) else {
            return false
        }

        return applySlotWidth(
            workspaceIndex: workspaceIndex,
            slotIndex: slotIndex,
            observedWidth: observedWidth,
            viewportWidth: viewportWidth,
            persist: persist,
            originOnChange: .nativeGeometrySync,
            statusMessageOnPersist: nil
        )
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

    @discardableResult
    public func syncFocusedWindowMatch(
        workspaceID: String,
        slotID: String,
        candidate: WindowCandidate,
        matchConfidence: Double
    ) -> Bool {
        guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }),
              let slotIndex = workspaces[workspaceIndex].slots.firstIndex(where: { $0.id == slotID }),
              let orderedIndex = workspaces[workspaceIndex].slotOrder.firstIndex(of: slotID) else {
            return false
        }

        let bindingChanged = runtimeBindingNeedsRefresh(
            workspaces[workspaceIndex].slots[slotIndex].runtimeBinding,
            candidate: candidate,
            matchConfidence: matchConfidence
        )
        let selectionChanged =
            selectedWorkspaceID != workspaceID ||
            workspaces[workspaceIndex].activeSlotID != slotID ||
            workspaces[workspaceIndex].layoutState.activeIndex != orderedIndex ||
            workspaces[workspaceIndex].layoutState.centeredSlotID != slotID

        guard selectionChanged || bindingChanged else {
            return false
        }

        lastSelectionOrigin = .nativeFocusSync
        selectedWorkspaceID = workspaceID
        appendRecent(workspaceID)
        workspaces[workspaceIndex].activeSlotID = slotID
        workspaces[workspaceIndex].layoutState.activeIndex = orderedIndex
        workspaces[workspaceIndex].layoutState.centeredSlotID = slotID

        if bindingChanged {
            workspaces[workspaceIndex].slots[slotIndex].runtimeBinding = RuntimeBinding(
                processID: candidate.processID,
                windowID: candidate.windowID,
                matchConfidence: matchConfidence,
                state: .attached,
                lastSeenAt: .now
            )
            workspaces[workspaceIndex].slots[slotIndex].updatedAt = .now
        }

        if selectionChanged || bindingChanged {
            workspaces[workspaceIndex].updatedAt = .now
            persistSoon()
        }

        return true
    }

    @discardableResult
    public func refreshRuntimeBinding(
        workspaceID: String,
        slotID: String,
        candidate: WindowCandidate,
        matchConfidence: Double
    ) -> Bool {
        guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }),
              let slotIndex = workspaces[workspaceIndex].slots.firstIndex(where: { $0.id == slotID }) else {
            return false
        }

        guard runtimeBindingNeedsRefresh(
            workspaces[workspaceIndex].slots[slotIndex].runtimeBinding,
            candidate: candidate,
            matchConfidence: matchConfidence
        ) else {
            return false
        }

        workspaces[workspaceIndex].slots[slotIndex].runtimeBinding = RuntimeBinding(
            processID: candidate.processID,
            windowID: candidate.windowID,
            matchConfidence: matchConfidence,
            state: .attached,
            lastSeenAt: .now
        )
        workspaces[workspaceIndex].slots[slotIndex].updatedAt = .now
        workspaces[workspaceIndex].updatedAt = .now
        persistSoon()
        return true
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

    @discardableResult
    private func applySlotWidth(
        workspaceIndex: Int,
        slotIndex: Int,
        observedWidth: Double,
        viewportWidth: Double,
        persist: Bool,
        originOnChange: SelectionOrigin?,
        statusMessageOnPersist: String?
    ) -> Bool {
        guard viewportWidth > 0, observedWidth > 0 else { return false }

        let currentPolicy = workspaces[workspaceIndex].slots[slotIndex].widthPolicy
        let minimum = currentPolicy.minimum ?? 320
        let maximum = currentPolicy.maximum ?? viewportWidth
        let clampedWidth = min(max(observedWidth, minimum), maximum)
        let fraction = min(max(clampedWidth / viewportWidth, 0.2), 1.25)

        let currentFraction = currentPolicy.value ?? 0
        let didChange =
            currentPolicy.mode != .fraction ||
            abs(currentFraction - fraction) > 0.0001

        guard didChange else { return false }

        workspaces[workspaceIndex].slots[slotIndex].widthPolicy.mode = .fraction
        workspaces[workspaceIndex].slots[slotIndex].widthPolicy.value = fraction
        workspaces[workspaceIndex].slots[slotIndex].updatedAt = .now
        workspaces[workspaceIndex].updatedAt = .now

        if let originOnChange {
            lastSelectionOrigin = originOnChange
        }

        if persist {
            if let statusMessageOnPersist {
                statusMessage = statusMessageOnPersist
            }
            persistSoon()
        }

        return true
    }

    private func persistSoon() {
        let state = currentPersistedState()
        Task {
            try? await store.saveState(state)
        }
    }

    private func normalizeLegacyBundleIDs(in state: PersistedWorkspaceState) -> PersistedWorkspaceState {
        var normalized = state
        normalized.workspaces = normalizeLegacyBundleIDs(in: state.workspaces)
        return normalized
    }

    private func normalizeLegacyBundleIDs(in workspaces: [Workspace]) -> [Workspace] {
        workspaces.map { workspace in
            var workspace = workspace
            workspace.slots = workspace.slots.map { slot in
                var slot = slot
                if slot.appBinding?.bundleID == "dev.tether.desktop" {
                    slot.appBinding?.bundleID = "com.t3tools.tether"
                    slot.updatedAt = .now
                }
                return slot
            }
            return workspace
        }
    }

    private func runtimeBindingNeedsRefresh(
        _ binding: RuntimeBinding?,
        candidate: WindowCandidate,
        matchConfidence: Double
    ) -> Bool {
        guard let binding else { return true }

        if binding.processID != candidate.processID {
            return true
        }
        if binding.windowID != candidate.windowID {
            return true
        }
        if binding.state != .attached {
            return true
        }
        if abs(binding.matchConfidence - matchConfidence) > 0.05 {
            return true
        }

        return false
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
