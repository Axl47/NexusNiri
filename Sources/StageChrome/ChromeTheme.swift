import AppKit
import SharedTypes
import SwiftUI

public enum ChromeMetrics {
    public static let sidebarWidth: CGFloat = 52
    public static let topbarHeight: CGFloat = 36
    public static let slotHeaderHeight: CGFloat = 28
    public static let stripIndicatorHeight: CGFloat = 6
    public static let slotGap: CGFloat = 2
    public static let workspaceIndicatorSize: CGFloat = 34

    public static func stageGeometry(for size: CGSize) -> StageGeometry {
        StageGeometry(
            viewportWidth: size.width,
            viewportHeight: size.height,
            sidebarWidth: sidebarWidth,
            topbarHeight: topbarHeight,
            slotHeaderHeight: slotHeaderHeight,
            stripIndicatorHeight: stripIndicatorHeight,
            slotGap: slotGap
        )
    }
}

public enum ChromeTheme {
    public static let chromeBackground = Color.white.opacity(0.07)
    public static let surface = Color.white.opacity(0.04)
    public static let surfaceHover = Color.white.opacity(0.08)
    public static let textPrimary = Color.white.opacity(0.92)
    public static let textSecondary = Color.white.opacity(0.50)
    public static let textTertiary = Color.white.opacity(0.28)
    public static let border = Color.white.opacity(0.08)
    public static let accent = Color(hue: 248.0 / 360.0, saturation: 0.58, brightness: 0.62)
    public static let accentDim = Color(hue: 248.0 / 360.0, saturation: 0.58, brightness: 0.62).opacity(0.20)
    public static let windowBackground = Color(nsColor: NSColor(calibratedWhite: 0.08, alpha: 1.0))
}

public struct TranslucentChromeBackground: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .withinWindow
        view.material = .hudWindow
        view.state = .active
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.blendingMode = .withinWindow
        nsView.material = .hudWindow
        nsView.state = .active
    }
}
