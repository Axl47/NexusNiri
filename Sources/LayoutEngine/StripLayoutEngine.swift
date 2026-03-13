import Foundation
import SharedTypes

public struct StripLayoutEngine: LayoutComputing {
    public init() {}

    public func planLayout(for workspace: Workspace, in geometry: StageGeometry) -> LayoutPlan {
        let orderedSlots = workspace.orderedSlots
        guard !orderedSlots.isEmpty else {
            return LayoutPlan(
                slotLayouts: [],
                contentWidth: geometry.stageWidth,
                scrollOffset: 0,
                visibleSlotIDs: [],
                parkedSlotIDs: [],
                activeSlotIndex: 0
            )
        }

        let activeIndex = max(0, min(workspace.layoutState.activeIndex, orderedSlots.count - 1))
        let viewportWidth = geometry.stageWidth
        let stageHeight = geometry.stageContentHeight

        var cursorX = 0.0
        var layouts: [SlotLayout] = []

        for (index, slot) in orderedSlots.enumerated() {
            let slotWidth = resolvedWidth(for: slot, viewportWidth: viewportWidth)
            let frame = RectValue(
                x: cursorX,
                y: 0,
                width: slotWidth,
                height: max(stageHeight - geometry.slotHeaderHeight, 160)
            )
            layouts.append(
                SlotLayout(
                    slotID: slot.id,
                    frame: frame,
                    isFocused: index == activeIndex
                )
            )
            cursorX += slotWidth + geometry.slotGap
        }

        let contentWidth = max(cursorX - geometry.slotGap, viewportWidth)
        let activeLayout = layouts[activeIndex]
        let centeredOffset = max(0, min(activeLayout.frame.midX - (viewportWidth / 2), contentWidth - viewportWidth))

        let visibleSlotIDs = layouts
            .filter { layout in
                let minVisibleX = centeredOffset
                let maxVisibleX = centeredOffset + viewportWidth
                return layout.frame.maxX >= minVisibleX && layout.frame.x <= maxVisibleX
            }
            .map(\.slotID)

        let parkedSlotIDs = orderedSlots
            .map(\.id)
            .filter { !visibleSlotIDs.contains($0) }

        return LayoutPlan(
            slotLayouts: layouts,
            contentWidth: contentWidth,
            scrollOffset: centeredOffset,
            visibleSlotIDs: visibleSlotIDs,
            parkedSlotIDs: parkedSlotIDs,
            activeSlotIndex: activeIndex
        )
    }

    private func resolvedWidth(for slot: Slot, viewportWidth: Double) -> Double {
        switch slot.widthPolicy.mode {
        case .fixed:
            return max(slot.widthPolicy.minimum ?? 240, slot.widthPolicy.value ?? 320)
        case .fullWidth:
            return viewportWidth
        case .fraction:
            let fraction = min(max(slot.widthPolicy.value ?? 0.4, 0.2), 1.25)
            let base = viewportWidth * fraction
            let minimum = slot.widthPolicy.minimum ?? 320
            let maximum = slot.widthPolicy.maximum ?? base
            return min(max(base, minimum), maximum)
        }
    }
}
