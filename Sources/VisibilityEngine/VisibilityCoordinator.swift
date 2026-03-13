import Foundation
import LayoutEngine
import SharedTypes

public actor VisibilityCoordinator: VisibilityCoordinating {
    private(set) var lastActions: [VisibilityAction] = []
    private(set) var panicModeEnabled = false

    public init() {}

    public func transition(
        from previousWorkspace: Workspace?,
        to nextWorkspace: Workspace,
        layout: LayoutPlan,
        windows: [WindowCandidate]
    ) async throws -> [VisibilityAction] {
        if panicModeEnabled {
            panicModeEnabled = false
        }

        let windowsBySlotBundleID = Dictionary(grouping: windows, by: { $0.bundleID ?? "" })
        var actions: [VisibilityAction] = []
        let activeSlotID = nextWorkspace.activeSlotID ?? nextWorkspace.orderedSlots.first?.id

        for slot in nextWorkspace.orderedSlots {
            let window = windowsBySlotBundleID[slot.appBinding?.bundleID ?? ""]?.first
            if slot.id == activeSlotID,
               let layoutFrame = layout.slotLayouts.first(where: { $0.slotID == slot.id })?.frame {
                actions.append(
                    VisibilityAction(
                        slotID: slot.id,
                        windowID: window?.windowID,
                        kind: .show,
                        targetFrame: layoutFrame
                    )
                )
            } else {
                actions.append(
                    VisibilityAction(
                        slotID: slot.id,
                        windowID: window?.windowID,
                        kind: .park,
                        targetFrame: RectValue(x: -24, y: 48, width: 12, height: 240)
                    )
                )
            }
        }

        if let previousWorkspace {
            let outgoingSlots = previousWorkspace.slotOrder.filter { !nextWorkspace.slotOrder.contains($0) }
            actions.append(contentsOf: outgoingSlots.map { VisibilityAction(slotID: $0, windowID: nil, kind: .park) })
        }

        lastActions = actions
        return actions
    }

    public func currentActions() -> [VisibilityAction] {
        lastActions
    }

    public func panicRevealAll() async throws {
        panicModeEnabled = true
        lastActions = lastActions.map { action in
            VisibilityAction(slotID: action.slotID, windowID: action.windowID, kind: .reveal, targetFrame: action.targetFrame)
        }
    }
}
