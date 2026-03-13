import CoreGraphics
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
    let geometry = ChromeMetrics.stageGeometry(for: CGSize(width: 1388, height: 864))

    #expect(geometry.stageWidth == 1388)
    #expect(geometry.stageHeight == 864)
    #expect(geometry.stageContentHeight == 858)
    #expect(geometry.edgePeekWidth == 16)
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
