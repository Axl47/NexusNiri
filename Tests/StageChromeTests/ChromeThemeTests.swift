import CoreGraphics
import SharedTypes
import Testing
@testable import StageChrome

@Test
func chromeMetricsMatchUiSpec() {
    #expect(ChromeMetrics.sidebarWidth == 52)
    #expect(ChromeMetrics.topbarHeight == 36)
    #expect(ChromeMetrics.slotHeaderHeight == 28)
    #expect(ChromeMetrics.stripIndicatorHeight == 6)
    #expect(ChromeMetrics.slotGap == 2)
    #expect(ChromeMetrics.edgePeekWidth == 16)
}

@Test
func chromeMetricsStageGeometryUsesVisibleViewportSpace() {
    let geometry = ChromeMetrics.stageGeometry(
        for: CGSize(width: 1388, height: 864),
        shellPresentationMode: .windowed
    )

    #expect(geometry.stageWidth == 1388)
    #expect(geometry.stageHeight == 864)
    #expect(geometry.stageContentHeight == 858)
    #expect(geometry.edgePeekWidth == 16)
}

@Test
func chromeMetricsStageGeometryUsesFullSafeViewportInNotchFillMode() {
    let geometry = ChromeMetrics.stageGeometry(
        for: CGSize(width: 1512, height: 945),
        shellPresentationMode: .notchFill
    )

    #expect(geometry.viewportWidth == 1512)
    #expect(geometry.viewportHeight == 945)
    #expect(geometry.sidebarWidth == 0)
    #expect(geometry.topbarHeight == 0)
    #expect(geometry.stageWidth == 1512)
    #expect(geometry.stageHeight == 945)
}

@Test
func shellDisplayLayoutConvertsScreenFramesIntoTopOrientedLocalFrames() {
    let layout = ShellDisplayLayout(
        windowFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeContentFrame: CGRect(x: 0, y: 0, width: 1512, height: 945),
        topLeftAuxiliaryFrame: CGRect(x: 0, y: 945, width: 640, height: 37),
        topRightAuxiliaryFrame: CGRect(x: 872, y: 945, width: 640, height: 37),
        hasCameraHousing: true
    )

    #expect(layout.localSafeContentFrame() == CGRect(x: 0, y: 37, width: 1512, height: 945))
    #expect(layout.localTopLeftAuxiliaryFrame() == CGRect(x: 0, y: 0, width: 640, height: 37))
    #expect(layout.localTopRightAuxiliaryFrame() == CGRect(x: 872, y: 0, width: 640, height: 37))
}

@Test
func stripIndicatorMetricsClampThumbForLongStrips() {
    let thumbWidth = StripIndicatorMetrics.thumbWidth(
        trackWidth: 200,
        contentWidth: 4000,
        viewportWidth: 180
    )

    #expect(thumbWidth == 12)
}

@Test
func stripIndicatorMetricsOffsetIsZeroWhenContentFitsViewport() {
    let offsetRatio = StripIndicatorMetrics.offsetRatio(
        scrollOffset: 120,
        contentWidth: 900,
        viewportWidth: 900
    )

    #expect(offsetRatio == 0)
}
