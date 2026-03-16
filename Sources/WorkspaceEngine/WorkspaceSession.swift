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

    public func addWorkspace(_ workspace: Workspace) {
        let normalizedWorkspace = normalizedWorkspaceForInsertion(workspace)
        workspaces.append(normalizedWorkspace)
        selectedWorkspaceID = normalizedWorkspace.id
        appendRecent(normalizedWorkspace.id)
        statusMessage = "Added \(normalizedWorkspace.name)."
        persistSoon()
    }

    @discardableResult
    public func addSlot(
        _ slot: Slot,
        to workspaceID: String,
        afterSlotID: String? = nil,
        selecting: Bool,
        origin: SelectionOrigin = .nexusNavigation
    ) -> Bool {
        guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
            return false
        }

        var slot = slot
        let now = Date()
        slot.workspaceID = workspaceID
        slot.createdAt = now
        slot.updatedAt = now

        guard workspaces[workspaceIndex].slots.contains(where: { $0.id == slot.id }) == false else {
            return false
        }

        workspaces[workspaceIndex].slots.append(slot)
        let insertIndex: Int
        if let afterSlotID,
           let orderedIndex = workspaces[workspaceIndex].slotOrder.firstIndex(of: afterSlotID) {
            insertIndex = orderedIndex + 1
        } else {
            insertIndex = workspaces[workspaceIndex].slotOrder.count
        }

        workspaces[workspaceIndex].slotOrder.insert(slot.id, at: insertIndex)

        let shouldSelect = selecting || workspaces[workspaceIndex].activeSlotID == nil
        if shouldSelect {
            lastSelectionOrigin = origin
            workspaces[workspaceIndex].activeSlotID = slot.id
        }

        workspaces[workspaceIndex].updatedAt = now
        updateSelectionState(forWorkspaceAt: workspaceIndex)
        if shouldSelect {
            selectedWorkspaceID = workspaceID
            appendRecent(workspaceID)
        }

        statusMessage = "Added \(slot.label)."
        persistSoon()
        return true
    }

    public func removeSelectedSlot() {
        guard let selectedWorkspaceID,
              let workspaceIndex = workspaces.firstIndex(where: { $0.id == selectedWorkspaceID }),
              let activeSlotID = workspaces[workspaceIndex].activeSlotID,
              let orderedIndex = workspaces[workspaceIndex].slotOrder.firstIndex(of: activeSlotID) else {
            return
        }

        workspaces[workspaceIndex].slots.removeAll { $0.id == activeSlotID }
        workspaces[workspaceIndex].slotOrder.removeAll { $0 == activeSlotID }

        let nextActiveSlotID: String?
        if workspaces[workspaceIndex].slotOrder.isEmpty {
            nextActiveSlotID = nil
        } else {
            let fallbackIndex = max(0, min(orderedIndex - 1, workspaces[workspaceIndex].slotOrder.count - 1))
            nextActiveSlotID = workspaces[workspaceIndex].slotOrder[safe: fallbackIndex]
                ?? workspaces[workspaceIndex].slotOrder.first
        }

        workspaces[workspaceIndex].activeSlotID = nextActiveSlotID
        workspaces[workspaceIndex].updatedAt = .now
        updateSelectionState(forWorkspaceAt: workspaceIndex)
        statusMessage = nextActiveSlotID == nil ? "Removed the last slot." : "Removed slot."
        persistSoon()
    }

    @discardableResult
    public func moveSelectedSlotLeft() -> Bool {
        guard let workspace = selectedWorkspace,
              let activeSlotID = workspace.activeSlotID,
              let currentIndex = workspace.slotOrder.firstIndex(of: activeSlotID) else {
            return false
        }

        return moveSlot(id: activeSlotID, in: workspace.id, to: currentIndex - 1)
    }

    @discardableResult
    public func moveSelectedSlotRight() -> Bool {
        guard let workspace = selectedWorkspace,
              let activeSlotID = workspace.activeSlotID,
              let currentIndex = workspace.slotOrder.firstIndex(of: activeSlotID) else {
            return false
        }

        return moveSlot(id: activeSlotID, in: workspace.id, to: currentIndex + 1)
    }

    @discardableResult
    public func toggleSelectedWorkspaceAutoAddPolicy() -> AutoAddPolicy? {
        guard let selectedWorkspaceID,
              let workspaceIndex = workspaces.firstIndex(where: { $0.id == selectedWorkspaceID }) else {
            return nil
        }

        let nextPolicy: AutoAddPolicy = switch workspaces[workspaceIndex].autoAddPolicy {
        case .disabled:
            .focusedStandardWindow
        case .focusedStandardWindow:
            .disabled
        }

        workspaces[workspaceIndex].autoAddPolicy = nextPolicy
        workspaces[workspaceIndex].updatedAt = .now
        statusMessage = nextPolicy == .disabled ? "Auto-add disabled." : "Auto-add enabled."
        persistSoon()
        return nextPolicy
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
    private func moveSlot(id: String, in workspaceID: String, to destinationIndex: Int) -> Bool {
        guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }),
              let sourceIndex = workspaces[workspaceIndex].slotOrder.firstIndex(of: id),
              workspaces[workspaceIndex].slotOrder.isEmpty == false else {
            return false
        }

        let clampedDestinationIndex = min(max(destinationIndex, 0), workspaces[workspaceIndex].slotOrder.count - 1)
        guard clampedDestinationIndex != sourceIndex else { return false }

        let movedID = workspaces[workspaceIndex].slotOrder.remove(at: sourceIndex)
        workspaces[workspaceIndex].slotOrder.insert(movedID, at: clampedDestinationIndex)
        workspaces[workspaceIndex].updatedAt = .now
        updateSelectionState(forWorkspaceAt: workspaceIndex)
        statusMessage = "Moved slot."
        persistSoon()
        return true
    }

    private func normalizedWorkspaceForInsertion(_ workspace: Workspace) -> Workspace {
        var workspace = workspace
        let now = Date()
        workspace.updatedAt = now
        if workspace.createdAt > now {
            workspace.createdAt = now
        }
        workspace.slots = workspace.orderedSlots.enumerated().map { index, slot in
            var slot = slot
            slot.workspaceID = workspace.id
            slot.updatedAt = now
            if slot.createdAt > now {
                slot.createdAt = now
            }
            if workspace.slotOrder.isEmpty {
                workspace.slotOrder.append(slot.id)
            } else if workspace.slotOrder.contains(slot.id) == false {
                workspace.slotOrder.append(slot.id)
            }
            if workspace.layoutState.visibleSlotIDs.isEmpty && index < 2 {
                workspace.layoutState.visibleSlotIDs.append(slot.id)
            }
            return slot
        }
        if workspace.activeSlotID == nil {
            workspace.activeSlotID = workspace.slotOrder.first
        }
        updateSelectionState(for: &workspace)
        return workspace
    }

    private func updateSelectionState(forWorkspaceAt index: Int) {
        updateSelectionState(for: &workspaces[index])
    }

    private func updateSelectionState(for workspace: inout Workspace) {
        if let activeSlotID = workspace.activeSlotID,
           let activeIndex = workspace.slotOrder.firstIndex(of: activeSlotID) {
            workspace.layoutState.activeIndex = activeIndex
            workspace.layoutState.centeredSlotID = activeSlotID
        } else if let firstSlotID = workspace.slotOrder.first {
            workspace.activeSlotID = firstSlotID
            workspace.layoutState.activeIndex = 0
            workspace.layoutState.centeredSlotID = firstSlotID
        } else {
            workspace.activeSlotID = nil
            workspace.layoutState.activeIndex = 0
            workspace.layoutState.centeredSlotID = nil
            workspace.layoutState.visibleSlotIDs = []
            workspace.layoutState.parkedSlotIDs = []
        }
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
