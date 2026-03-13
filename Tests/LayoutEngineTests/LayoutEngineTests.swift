import Testing
import SharedTypes
@testable import LayoutEngine

@Test
func stripLayoutCentersActiveSlotAndShowsOnlyImmediateNeighborsAsEdgePeeks() throws {
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
    let leftPeek = try #require(plan.revealedFragments.first(where: { $0.kind == .leftPeek }))
    let rightPeek = try #require(plan.revealedFragments.first(where: { $0.kind == .rightPeek }))

    #expect(plan.activeSlotIndex == 1)
    #expect(plan.leadingPadding == 250)
    #expect(plan.trailingPadding == 350)
    #expect(plan.scrollOffset == 652)
    #expect(activeFrame.midX - plan.scrollOffset == geometry.stageWidth / 2)
    #expect(plan.visibleSlotIDs == ["a", "b", "c"])
    #expect(plan.parkedSlotIDs.isEmpty)
    #expect(plan.contentWidth == 2404)
    #expect(leftPeek.frame == RectValue(x: 284, y: 0, width: 14, height: 866))
    #expect(leftPeek.frame.width == 14)
    #expect(rightPeek.frame == RectValue(x: 902, y: 0, width: 14, height: 866))
    #expect(rightPeek.frame.width == 14)
    #expect(plan.occlusionBands == [
        RectValue(x: 0, y: 0, width: 284, height: 866),
        RectValue(x: 298, y: 0, width: 2, height: 866),
        RectValue(x: 900, y: 0, width: 2, height: 866),
        RectValue(x: 916, y: 0, width: 284, height: 866),
    ])
}

@Test
func stripLayoutCentersFirstSlotWithVirtualLeadingPadding() {
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
    let activeFragment = try! #require(plan.revealedFragments.first(where: { $0.kind == .active }))
    let rightPeek = try! #require(plan.revealedFragments.first(where: { $0.kind == .rightPeek }))

    #expect(plan.scrollOffset == 0)
    #expect(plan.leadingPadding == 250)
    #expect(plan.trailingPadding == 350)
    #expect(plan.visibleSlotIDs == ["a", "b"])
    #expect(plan.parkedSlotIDs == ["c"])
    #expect(activeFragment.frame == RectValue(x: 250, y: 0, width: 700, height: 866))
    #expect(rightPeek.frame == RectValue(x: 952, y: 0, width: 14, height: 866))
}

@Test
func stripLayoutCentersLastSlotWithVirtualTrailingPadding() {
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
    let leftPeek = try! #require(plan.revealedFragments.first(where: { $0.kind == .leftPeek }))
    let activeFragment = try! #require(plan.revealedFragments.first(where: { $0.kind == .active }))

    #expect(plan.scrollOffset == 1204)
    #expect(plan.visibleSlotIDs == ["b", "c"])
    #expect(plan.parkedSlotIDs == ["a"])
    #expect(leftPeek.frame == RectValue(x: 334, y: 0, width: 14, height: 866))
    #expect(activeFragment.frame == RectValue(x: 350, y: 0, width: 500, height: 866))
}
