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
                leadingPadding: 0,
                trailingPadding: 0,
                visibleSlotIDs: [],
                parkedSlotIDs: [],
                activeSlotIndex: 0,
                revealedFragments: [],
                occlusionBands: []
            )
        }

        let activeIndex = max(0, min(workspace.layoutState.activeIndex, orderedSlots.count - 1))
        let viewportWidth = geometry.stageWidth
        let stageHeight = geometry.stageContentHeight
        let slotWidths = orderedSlots.map { resolvedWidth(for: $0, viewportWidth: viewportWidth) }
        let leadingPadding = max((viewportWidth - (slotWidths.first ?? viewportWidth)) / 2, 0)
        let trailingPadding = max((viewportWidth - (slotWidths.last ?? viewportWidth)) / 2, 0)

        var cursorX = leadingPadding
        var layouts: [SlotLayout] = []

        for (index, slot) in orderedSlots.enumerated() {
            let slotWidth = slotWidths[index]
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

        let contentWidth = max(cursorX - geometry.slotGap + trailingPadding, viewportWidth)
        let activeLayout = layouts[activeIndex]
        let centeredOffset = max(0, min(activeLayout.frame.midX - (viewportWidth / 2), contentWidth - viewportWidth))
        let visibleIndices = [
            activeIndex > 0 ? activeIndex - 1 : nil,
            activeIndex,
            activeIndex + 1 < orderedSlots.count ? activeIndex + 1 : nil,
        ].compactMap { $0 }
        let visibleSlotIDs = visibleIndices.map { orderedSlots[$0].id }
        let revealedFragments = revealedFragments(
            for: layouts,
            visibleIndices: visibleIndices,
            activeIndex: activeIndex,
            scrollOffset: centeredOffset,
            viewportWidth: viewportWidth,
            edgePeekWidth: geometry.edgePeekWidth
        )
        let occlusionBands = occlusionBands(
            from: revealedFragments.map(\.frame),
            viewportWidth: viewportWidth,
            stageHeight: activeLayout.frame.height
        )

        let parkedSlotIDs = orderedSlots
            .map(\.id)
            .filter { !visibleSlotIDs.contains($0) }

        return LayoutPlan(
            slotLayouts: layouts,
            contentWidth: contentWidth,
            scrollOffset: centeredOffset,
            leadingPadding: leadingPadding,
            trailingPadding: trailingPadding,
            visibleSlotIDs: visibleSlotIDs,
            parkedSlotIDs: parkedSlotIDs,
            activeSlotIndex: activeIndex,
            revealedFragments: revealedFragments,
            occlusionBands: occlusionBands
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

    private func revealedFragments(
        for layouts: [SlotLayout],
        visibleIndices: [Int],
        activeIndex: Int,
        scrollOffset: Double,
        viewportWidth: Double,
        edgePeekWidth: Double
    ) -> [RevealedSlotFragment] {
        guard !layouts.isEmpty else { return [] }

        let viewportRect = RectValue(x: 0, y: 0, width: viewportWidth, height: layouts[activeIndex].frame.height)
        let activeViewportFrame = RectValue(
            x: layouts[activeIndex].frame.x - scrollOffset,
            y: layouts[activeIndex].frame.y,
            width: layouts[activeIndex].frame.width,
            height: layouts[activeIndex].frame.height
        )
        guard let activeFragment = intersection(activeViewportFrame, viewportRect) else {
            return []
        }

        let leftPeekRect = RectValue(
            x: max(activeFragment.x - edgePeekWidth, 0),
            y: 0,
            width: min(edgePeekWidth, activeFragment.x),
            height: layouts[activeIndex].frame.height
        )
        let rightPeekRect = RectValue(
            x: min(activeFragment.maxX, viewportWidth),
            y: 0,
            width: min(edgePeekWidth, max(viewportWidth - activeFragment.maxX, 0)),
            height: layouts[activeIndex].frame.height
        )

        return visibleIndices.compactMap { index in
            let layout = layouts[index]
            let viewportFrame = RectValue(
                x: layout.frame.x - scrollOffset,
                y: layout.frame.y,
                width: layout.frame.width,
                height: layout.frame.height
            )

            let fragmentFrame: RectValue?
            let kind: RevealedSlotFragmentKind

            switch index {
            case activeIndex:
                fragmentFrame = activeFragment
                kind = .active
            case activeIndex - 1:
                fragmentFrame = leftPeekRect.width > 0 ? intersection(viewportFrame, leftPeekRect) : nil
                kind = .leftPeek
            case activeIndex + 1:
                fragmentFrame = rightPeekRect.width > 0 ? intersection(viewportFrame, rightPeekRect) : nil
                kind = .rightPeek
            default:
                return nil
            }

            guard let fragmentFrame, fragmentFrame.width > 0 else {
                return nil
            }

            return RevealedSlotFragment(slotID: layout.slotID, kind: kind, frame: fragmentFrame)
        }
    }

    private func occlusionBands(
        from visibleFrames: [RectValue],
        viewportWidth: Double,
        stageHeight: Double
    ) -> [RectValue] {
        guard viewportWidth > 0, stageHeight > 0 else { return [] }

        let merged = visibleFrames
            .filter { $0.width > 0 }
            .sorted { $0.x < $1.x }
            .reduce(into: [RectValue]()) { result, frame in
                guard let last = result.last else {
                    result.append(frame)
                    return
                }

                if frame.x <= last.maxX {
                    result[result.count - 1] = RectValue(
                        x: last.x,
                        y: 0,
                        width: max(last.maxX, frame.maxX) - last.x,
                        height: stageHeight
                    )
                } else {
                    result.append(frame)
                }
            }

        var cursorX = 0.0
        var bands: [RectValue] = []

        for frame in merged {
            if frame.x > cursorX {
                bands.append(RectValue(x: cursorX, y: 0, width: frame.x - cursorX, height: stageHeight))
            }
            cursorX = max(cursorX, frame.maxX)
        }

        if cursorX < viewportWidth {
            bands.append(RectValue(x: cursorX, y: 0, width: viewportWidth - cursorX, height: stageHeight))
        }

        return bands.filter { $0.width > 0 }
    }

    private func intersection(_ lhs: RectValue, _ rhs: RectValue) -> RectValue? {
        let x = max(lhs.x, rhs.x)
        let y = max(lhs.y, rhs.y)
        let maxX = min(lhs.maxX, rhs.maxX)
        let maxY = min(lhs.maxY, rhs.maxY)

        guard maxX > x, maxY > y else {
            return nil
        }

        return RectValue(
            x: x,
            y: y,
            width: maxX - x,
            height: maxY - y
        )
    }
}
