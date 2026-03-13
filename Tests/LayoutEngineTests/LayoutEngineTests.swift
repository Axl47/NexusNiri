import Testing
import SharedTypes
@testable import LayoutEngine

@Test
func stripLayoutCentersActiveSlotAndParksOffstageNeighbors() {
    let slots = [
        Slot(id: "a", workspaceID: "w", kind: .externalWindow, label: "Editor", widthPolicy: SizePolicy(mode: .fraction, value: 0.55), layoutRole: .primary),
        Slot(id: "b", workspaceID: "w", kind: .externalWindow, label: "Zen", widthPolicy: SizePolicy(mode: .fraction, value: 0.45), layoutRole: .secondary),
        Slot(id: "c", workspaceID: "w", kind: .hybrid, label: "Tether", widthPolicy: SizePolicy(mode: .fraction, value: 0.40), layoutRole: .support),
    ]
    let workspace = Workspace(
        id: "w",
        name: "API",
        activeSlotID: "b",
        slotOrder: slots.map(\.id),
        layoutState: LayoutState(activeIndex: 1, centeredSlotID: "b"),
        slots: slots
    )
    let geometry = StageGeometry(viewportWidth: 1440, viewportHeight: 900)
    let engine = StripLayoutEngine()

    let plan = engine.planLayout(for: workspace, in: geometry)

    #expect(plan.activeSlotIndex == 1)
    #expect(plan.scrollOffset >= 0)
    #expect(plan.visibleSlotIDs.contains("b"))
    #expect(plan.contentWidth >= geometry.stageWidth)
}
