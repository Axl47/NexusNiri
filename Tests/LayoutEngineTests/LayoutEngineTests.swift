import Testing
import SharedTypes
@testable import LayoutEngine

@Test
func stripLayoutCentersActiveSlotAndParksOffstageNeighbors() throws {
    let slots = [
        Slot(id: "a", workspaceID: "w", kind: .externalWindow, label: "Editor", widthPolicy: SizePolicy(mode: .fixed, value: 700), layoutRole: .primary),
        Slot(id: "b", workspaceID: "w", kind: .externalWindow, label: "Zen", widthPolicy: SizePolicy(mode: .fixed, value: 600), layoutRole: .secondary),
        Slot(id: "c", workspaceID: "w", kind: .hybrid, label: "Tether", widthPolicy: SizePolicy(mode: .fixed, value: 500), layoutRole: .support),
    ]
    let workspace = Workspace(
        id: "w",
        name: "API",
        activeSlotID: "b",
        slotOrder: slots.map(\.id),
        layoutState: LayoutState(activeIndex: 1, centeredSlotID: "b"),
        slots: slots
    )
    let geometry = StageGeometry(
        viewportWidth: 1200,
        viewportHeight: 900,
        sidebarWidth: 0,
        topbarHeight: 0
    )
    let engine = StripLayoutEngine()

    let plan = engine.planLayout(for: workspace, in: geometry)
    let activeFrame = try #require(plan.slotLayouts.first(where: { $0.slotID == "b" })?.frame)

    #expect(plan.activeSlotIndex == 1)
    #expect(plan.scrollOffset == 402)
    #expect(activeFrame.midX - plan.scrollOffset == geometry.stageWidth / 2)
    #expect(plan.visibleSlotIDs.contains("b"))
    #expect(plan.visibleSlotIDs == ["a", "b", "c"])
    #expect(plan.parkedSlotIDs.isEmpty)
    #expect(plan.contentWidth == 1804)
}

@Test
func stripLayoutClampsFirstSlotToLeadingEdge() {
    let slots = [
        Slot(id: "a", workspaceID: "w", kind: .externalWindow, label: "Editor", widthPolicy: SizePolicy(mode: .fixed, value: 700), layoutRole: .primary),
        Slot(id: "b", workspaceID: "w", kind: .externalWindow, label: "Zen", widthPolicy: SizePolicy(mode: .fixed, value: 600), layoutRole: .secondary),
        Slot(id: "c", workspaceID: "w", kind: .externalWindow, label: "Docs", widthPolicy: SizePolicy(mode: .fixed, value: 500), layoutRole: .support),
    ]
    let workspace = Workspace(
        id: "w",
        name: "API",
        activeSlotID: "a",
        slotOrder: slots.map(\.id),
        layoutState: LayoutState(activeIndex: 0, centeredSlotID: "a"),
        slots: slots
    )
    let geometry = StageGeometry(
        viewportWidth: 1200,
        viewportHeight: 900,
        sidebarWidth: 0,
        topbarHeight: 0
    )

    let plan = StripLayoutEngine().planLayout(for: workspace, in: geometry)

    #expect(plan.scrollOffset == 0)
    #expect(plan.visibleSlotIDs == ["a", "b"])
    #expect(plan.parkedSlotIDs == ["c"])
}

@Test
func stripLayoutClampsLastSlotToTrailingEdge() {
    let slots = [
        Slot(id: "a", workspaceID: "w", kind: .externalWindow, label: "Editor", widthPolicy: SizePolicy(mode: .fixed, value: 700), layoutRole: .primary),
        Slot(id: "b", workspaceID: "w", kind: .externalWindow, label: "Zen", widthPolicy: SizePolicy(mode: .fixed, value: 600), layoutRole: .secondary),
        Slot(id: "c", workspaceID: "w", kind: .externalWindow, label: "Docs", widthPolicy: SizePolicy(mode: .fixed, value: 500), layoutRole: .support),
    ]
    let workspace = Workspace(
        id: "w",
        name: "API",
        activeSlotID: "c",
        slotOrder: slots.map(\.id),
        layoutState: LayoutState(activeIndex: 2, centeredSlotID: "c"),
        slots: slots
    )
    let geometry = StageGeometry(
        viewportWidth: 1200,
        viewportHeight: 900,
        sidebarWidth: 0,
        topbarHeight: 0
    )

    let plan = StripLayoutEngine().planLayout(for: workspace, in: geometry)

    #expect(plan.scrollOffset == 604)
    #expect(plan.visibleSlotIDs == ["a", "b", "c"])
    #expect(plan.parkedSlotIDs.isEmpty)
}
