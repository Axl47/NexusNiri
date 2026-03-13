import Testing
@testable import StageChrome

@Test
func chromeMetricsMatchUiSpec() {
    #expect(ChromeMetrics.sidebarWidth == 52)
    #expect(ChromeMetrics.topbarHeight == 36)
    #expect(ChromeMetrics.slotHeaderHeight == 28)
    #expect(ChromeMetrics.stripIndicatorHeight == 6)
    #expect(ChromeMetrics.slotGap == 2)
}
