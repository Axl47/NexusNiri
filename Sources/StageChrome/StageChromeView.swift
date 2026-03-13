import AppKit
import LayoutEngine
import Observation
import SharedTypes
import SwiftUI
import WorkspaceEngine

@MainActor
public struct StageChromeView: View {
    @Bindable private var session: WorkspaceSession
    private let layoutEngine: any LayoutComputing
    private let diagnosticsSnapshot: DiagnosticsSnapshot
    private let shellPresentationMode: ShellPresentationMode
    private let shellDisplayLayout: ShellDisplayLayout?
    private let onOpenDiagnostics: () -> Void
    private let onRequestAccessibility: () -> Void
    private let onRefreshDiagnostics: () -> Void
    private let onRevealAll: () -> Void
    private let onLayoutDidUpdate: (Workspace, LayoutPlan) async -> Void
    private let onStageViewportFrameChanged: (CGRect) -> Void
    private let onShellWindowChanged: (NSWindow?) -> Void

    public init(
        session: WorkspaceSession,
        layoutEngine: any LayoutComputing,
        diagnosticsSnapshot: DiagnosticsSnapshot,
        shellPresentationMode: ShellPresentationMode,
        shellDisplayLayout: ShellDisplayLayout?,
        onOpenDiagnostics: @escaping () -> Void,
        onRequestAccessibility: @escaping () -> Void,
        onRefreshDiagnostics: @escaping () -> Void,
        onRevealAll: @escaping () -> Void,
        onLayoutDidUpdate: @escaping (Workspace, LayoutPlan) async -> Void,
        onStageViewportFrameChanged: @escaping (CGRect) -> Void,
        onShellWindowChanged: @escaping (NSWindow?) -> Void
    ) {
        self.session = session
        self.layoutEngine = layoutEngine
        self.diagnosticsSnapshot = diagnosticsSnapshot
        self.shellPresentationMode = shellPresentationMode
        self.shellDisplayLayout = shellDisplayLayout
        self.onOpenDiagnostics = onOpenDiagnostics
        self.onRequestAccessibility = onRequestAccessibility
        self.onRefreshDiagnostics = onRefreshDiagnostics
        self.onRevealAll = onRevealAll
        self.onLayoutDidUpdate = onLayoutDidUpdate
        self.onStageViewportFrameChanged = onStageViewportFrameChanged
        self.onShellWindowChanged = onShellWindowChanged
    }

    public var body: some View {
        Group {
            switch shellPresentationMode {
            case .windowed:
                windowedShell
            case .notchFill:
                GeometryReader { proxy in
                    notchFillShell(
                        displayLayout: shellDisplayLayout ?? ShellDisplayLayout(
                            windowFrame: CGRect(origin: .zero, size: proxy.size),
                            safeContentFrame: CGRect(origin: .zero, size: proxy.size),
                            hasCameraHousing: false
                        )
                    )
                }
            }
        }
        .frame(minWidth: 1120, minHeight: 760)
        .background(ChromeTheme.windowBackground)
    }

    private var windowedShell: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                topbar
                Divider().overlay(ChromeTheme.border)
                windowedViewport
            }
        }
    }

    private var sidebar: some View {
        ZStack(alignment: .leading) {
            ChromeBackdrop()

            VStack(spacing: 10) {
                VStack(spacing: 8) {
                    ForEach(Array(session.workspaces.enumerated()), id: \.element.id) { index, workspace in
                        WorkspaceButton(
                            number: index + 1,
                            workspace: workspace,
                            isSelected: session.selectedWorkspaceID == workspace.id
                        ) {
                            var transaction = Transaction()
                            transaction.animation = nil
                            withTransaction(transaction) {
                                session.selectWorkspace(id: workspace.id)
                            }
                        }
                    }
                }

                Spacer(minLength: 12)

                VStack(spacing: 8) {
                    UtilityButton(symbol: "plus", action: {
                        session.addWorkspace()
                    })
                    UtilityButton(symbol: "arrow.clockwise", action: onRefreshDiagnostics)
                    UtilityButton(symbol: "exclamationmark.triangle", action: onRevealAll)
                    UtilityButton(symbol: "slider.horizontal.3", action: onOpenDiagnostics)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 9)

            if let index = session.workspaces.firstIndex(where: { $0.id == session.selectedWorkspaceID }) {
                Rectangle()
                    .fill(ChromeTheme.accent)
                    .frame(width: 3, height: 16)
                    .offset(y: CGFloat(index) * 42)
                    .padding(.leading, 1)
                    .animation(.easeOut(duration: 0.1), value: index)
            }
        }
        .frame(width: ChromeMetrics.sidebarWidth)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(ChromeTheme.border)
                .frame(width: 0.5)
        }
    }

    private var topbar: some View {
        ZStack {
            ChromeBackdrop()

            HStack(spacing: 10) {
                Text(session.selectedWorkspace?.name ?? "No Workspace")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ChromeTheme.textPrimary)

                Circle()
                    .fill(ChromeTheme.textTertiary)
                    .frame(width: 2, height: 2)

                Text(metadataText)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(ChromeTheme.textSecondary)

                Spacer(minLength: 12)

                if let status = accessibilityPermissionStatus, status.state != .granted {
                    Text(accessibilityWarningText(for: status))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange.opacity(0.92))
                        .lineLimit(1)

                    Button("Enable Accessibility") {
                        onRequestAccessibility()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ChromeTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 8).fill(ChromeTheme.accentDim))
                }

                HStack(spacing: 10) {
                    Button(action: session.selectPreviousSlot) {
                        Image(systemName: "arrow.left")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ChromeTheme.textSecondary)

                    Button(action: session.selectNextSlot) {
                        Image(systemName: "arrow.right")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ChromeTheme.textSecondary)
                }
                .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 14)
        }
        .frame(height: ChromeMetrics.topbarHeight)
    }

    private var windowedViewport: some View {
        GeometryReader { proxy in
            stageViewportContent(for: proxy.size)
        }
    }

    private func notchFillShell(displayLayout: ShellDisplayLayout) -> some View {
        let safeContentFrame = displayLayout.localSafeContentFrame().integral
        let leadingFrame = notchLeadingFrame(in: displayLayout, safeContentFrame: safeContentFrame)
        let trailingFrame = notchTrailingFrame(in: displayLayout, safeContentFrame: safeContentFrame)

        return ZStack(alignment: .topLeading) {
            ChromeBackdrop()

            stageViewportContent(for: safeContentFrame.size)
                .frame(width: safeContentFrame.width, height: safeContentFrame.height)
                .offset(x: safeContentFrame.minX, y: safeContentFrame.minY)

            notchLeadingChrome
                .frame(width: leadingFrame.width, height: leadingFrame.height)
                .offset(x: leadingFrame.minX, y: leadingFrame.minY)

            notchTrailingChrome
                .frame(width: trailingFrame.width, height: trailingFrame.height)
                .offset(x: trailingFrame.minX, y: trailingFrame.minY)
        }
    }

    @ViewBuilder
    private func stageViewportContent(for viewportSize: CGSize) -> some View {
        let geometry = ChromeMetrics.stageGeometry(
            for: viewportSize,
            shellPresentationMode: shellPresentationMode
        )
        let workspace = session.selectedWorkspace
        let layout = workspace.map { layoutEngine.planLayout(for: $0, in: geometry) }

        Group {
            if let workspace, let layout {
                StageViewportView(
                    session: session,
                    workspace: workspace,
                    layout: layout,
                    geometry: geometry,
                    onLayoutDidUpdate: onLayoutDidUpdate
                )
            } else {
                emptyState
            }
        }
        .background(
            ScreenSpaceFrameReporter(
                onChange: onStageViewportFrameChanged,
                onWindowChange: onShellWindowChanged
            )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var notchLeadingChrome: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(session.workspaces.enumerated()), id: \.element.id) { index, workspace in
                        WorkspaceButton(
                            number: index + 1,
                            workspace: workspace,
                            isSelected: session.selectedWorkspaceID == workspace.id
                        ) {
                            var transaction = Transaction()
                            transaction.animation = nil
                            withTransaction(transaction) {
                                session.selectWorkspace(id: workspace.id)
                            }
                        }
                    }
                }
                .padding(.leading, 2)
            }

            HStack(spacing: 8) {
                UtilityButton(symbol: "plus", action: {
                    session.addWorkspace()
                })
                UtilityButton(symbol: "arrow.clockwise", action: onRefreshDiagnostics)
                UtilityButton(symbol: "exclamationmark.triangle", action: onRevealAll)
                UtilityButton(symbol: "slider.horizontal.3", action: onOpenDiagnostics)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(NotchChromeBackground())
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var notchTrailingChrome: some View {
        HStack(spacing: 10) {
            Text(metadataText)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(ChromeTheme.textSecondary)
                .lineLimit(1)

            if let status = accessibilityPermissionStatus, status.state != .granted {
                Button("Enable Accessibility") {
                    onRequestAccessibility()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ChromeTheme.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 8).fill(ChromeTheme.accentDim))
            }

            HStack(spacing: 10) {
                Button(action: session.selectPreviousSlot) {
                    Image(systemName: "arrow.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(ChromeTheme.textSecondary)

                Button(action: session.selectNextSlot) {
                    Image(systemName: "arrow.right")
                }
                .buttonStyle(.plain)
                .foregroundStyle(ChromeTheme.textSecondary)
            }
            .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(NotchChromeBackground())
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func notchLeadingFrame(in displayLayout: ShellDisplayLayout, safeContentFrame: CGRect) -> CGRect {
        if let frame = displayLayout.localTopLeftAuxiliaryFrame(), frame.isEmpty == false {
            return frame.insetBy(dx: 8, dy: 6)
        }

        return CGRect(
            x: safeContentFrame.minX + 10,
            y: safeContentFrame.minY + 8,
            width: max(260, min(safeContentFrame.width * 0.52, 560)),
            height: ChromeMetrics.workspaceIndicatorSize + 12
        )
    }

    private func notchTrailingFrame(in displayLayout: ShellDisplayLayout, safeContentFrame: CGRect) -> CGRect {
        if let frame = displayLayout.localTopRightAuxiliaryFrame(), frame.isEmpty == false {
            return frame.insetBy(dx: 8, dy: 6)
        }

        let width = max(240, min(safeContentFrame.width * 0.38, 420))
        return CGRect(
            x: safeContentFrame.maxX - width - 10,
            y: safeContentFrame.minY + 8,
            width: width,
            height: ChromeMetrics.topbarHeight + 10
        )
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No apps in this workspace")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ChromeTheme.textSecondary)
            Text("Use the plus button in the sidebar to add a workspace.")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(ChromeTheme.textTertiary)
        }
    }

    private var metadataText: String {
        guard let workspace = session.selectedWorkspace else { return "0 apps" }
        let count = workspace.slotOrder.count
        guard count > 0 else { return "0 apps" }
        let index = min(workspace.slotOrder.count, session.selectedSlotIndex + 1)
        return count == 1 ? "1 app" : "\(count) apps · \(index) / \(count)"
    }

    private var accessibilityPermissionStatus: PermissionStatus? {
        diagnosticsSnapshot.permissions.first(where: { $0.kind == .accessibility })
    }

    private func accessibilityWarningText(for status: PermissionStatus) -> String {
        let buildIdentity = diagnosticsSnapshot.buildIdentity

        if buildIdentity.signingMode == .adHoc {
            return "Window staging blocked by ad-hoc dev signing."
        }

        if buildIdentity.launchedFromExpectedPath == false,
           buildIdentity.expectedInstallPath?.isEmpty == false {
            return "Window staging blocked until the installed Nexus.app is trusted."
        }

        if status.state == .denied {
            return "Window staging is blocked until Accessibility is granted."
        }

        return status.detail
    }
}

private struct WorkspaceButton: View {
    let number: Int
    let workspace: Workspace
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? ChromeTheme.accentDim : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(ChromeTheme.border, lineWidth: 0.5)
                        )

                    Text("\(number)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isSelected ? ChromeTheme.accent.opacity(0.95) : ChromeTheme.textSecondary)
                }
                .frame(width: ChromeMetrics.workspaceIndicatorSize, height: ChromeMetrics.workspaceIndicatorSize)

                Text(String(workspace.name.prefix(4)).uppercased())
                    .font(.system(size: 8, weight: .regular))
                    .tracking(0.4)
                    .foregroundStyle(ChromeTheme.textTertiary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct UtilityButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ChromeTheme.textSecondary)
                .frame(width: ChromeMetrics.workspaceIndicatorSize, height: ChromeMetrics.workspaceIndicatorSize)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(ChromeTheme.surface)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct StageViewportView: View {
    @Bindable var session: WorkspaceSession
    let workspace: Workspace
    let layout: LayoutPlan
    let geometry: StageGeometry
    let onLayoutDidUpdate: (Workspace, LayoutPlan) async -> Void

    @State private var layoutUpdateTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .bottom) {
            StageSurfaceView(workspace: workspace, layout: layout)

            if workspace.orderedSlots.isEmpty {
                EmptyWorkspaceOverlay()
            }

            if workspace.slotOrder.count != 1 {
                StripIndicatorView(
                    layout: layout,
                    viewportWidth: geometry.stageWidth,
                    showThumb: !workspace.orderedSlots.isEmpty
                )
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
            }
        }
        .overlay(alignment: .topLeading) {
            SlotHeaderStripView(
                workspace: workspace,
                layout: layout
            ) { slotID in
                session.selectSlot(id: slotID)
            }
        }
        .clipped()
        .onAppear {
            scheduleLayoutUpdate()
        }
        .onChange(of: layoutTaskKey) { _, _ in
            scheduleLayoutUpdate()
        }
        .onDisappear {
            layoutUpdateTask?.cancel()
            layoutUpdateTask = nil
        }
    }

    private var layoutTaskKey: LayoutTaskKey {
        LayoutTaskKey(layout: layout, workspaceID: workspace.id, activeSlotID: workspace.activeSlotID)
    }

    private func scheduleLayoutUpdate() {
        session.updateVisibility(using: layout)

        layoutUpdateTask?.cancel()
        let workspace = workspace
        let layout = layout

        layoutUpdateTask = Task { @MainActor in
            await onLayoutDidUpdate(workspace, layout)
        }
    }
}

private struct StageSurfaceView: View {
    let workspace: Workspace
    let layout: LayoutPlan

    var body: some View {
        GeometryReader { proxy in
            let stageLaneHeight = max(
                proxy.size.height - ChromeMetrics.slotHeaderHeight - ChromeMetrics.stripIndicatorHeight,
                0
            )

            ZStack(alignment: .topLeading) {
                ChromeTheme.windowBackground
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.02),
                        Color.clear,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                ForEach(workspace.orderedSlots) { slot in
                    if let slotLayout = layout.slotLayout(for: slot.id) {
                        StageSlotPresenceView(
                            slot: slot,
                            isFocused: workspace.activeSlotID == slot.id,
                            isVisible: layout.visibleSlotIDs.contains(slot.id)
                        )
                        .frame(width: slotLayout.frame.width, height: stageLaneHeight)
                        .offset(
                            x: slotLayout.frame.x - layout.scrollOffset,
                            y: ChromeMetrics.slotHeaderHeight
                        )
                    }
                }
            }
            .animation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.4), value: layout.scrollOffset)
            .animation(.easeOut(duration: 0.3), value: workspace.activeSlotID)
        }
    }
}

private struct StageSlotPresenceView: View {
    let slot: Slot
    let isFocused: Bool
    let isVisible: Bool

    var body: some View {
        Rectangle()
            .fill(isFocused ? ChromeTheme.stageSurfaceFocused : ChromeTheme.stageSurface)
            .overlay {
                Rectangle()
                    .stroke(ChromeTheme.border, lineWidth: 0.5)
            }
            .overlay(alignment: .bottomLeading) {
                Rectangle()
                    .fill(slotTintColor(for: slot).opacity(isFocused ? 0.5 : 0.22))
                    .frame(width: min(72, max(24, CGFloat(slot.label.count) * 8)), height: 2)
                    .padding(.leading, 16)
                    .padding(.bottom, 16)
            }
            .opacity(isFocused ? 1.0 : (isVisible ? 0.5 : 0.18))
        .animation(.easeOut(duration: 0.3), value: isFocused)
    }
}

private struct SlotHeaderStripView: View {
    let workspace: Workspace
    let layout: LayoutPlan
    let onSelectSlot: (String) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(workspace.orderedSlots) { slot in
                if let slotLayout = layout.slotLayout(for: slot.id) {
                    SlotHeaderView(
                        slot: slot,
                        isFocused: workspace.activeSlotID == slot.id
                    ) {
                        onSelectSlot(slot.id)
                    }
                    .frame(width: slotLayout.frame.width, height: ChromeMetrics.slotHeaderHeight)
                    .offset(x: slotLayout.frame.x - layout.scrollOffset)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.4), value: layout.scrollOffset)
        .animation(.easeOut(duration: 0.3), value: workspace.activeSlotID)
    }
}

private struct SlotHeaderView: View {
    let slot: Slot
    let isFocused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(slotTintColor(for: slot))
                    .frame(width: 14, height: 14)
                    .overlay {
                        Text(String(slot.label.prefix(1)).uppercased())
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.white)
                    }

                Text(slot.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isFocused ? ChromeTheme.textPrimary : ChromeTheme.textSecondary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: ChromeMetrics.slotHeaderHeight)
            .background {
                ChromeTheme.chromeOcclusion
                    .overlay(isFocused ? ChromeTheme.surfaceHover : ChromeTheme.surface.opacity(0.82))
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(ChromeTheme.border)
                    .frame(height: 0.5)
            }
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(ChromeTheme.border.opacity(0.55))
                    .frame(width: 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isFocused ? 1.0 : 0.5)
        .animation(.easeOut(duration: 0.3), value: isFocused)
    }
}

private struct EmptyWorkspaceOverlay: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("No apps in this workspace")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ChromeTheme.textSecondary)
            Text("Use the plus button in the sidebar to add a workspace.")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(ChromeTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LayoutTaskKey: Hashable {
    let workspaceID: String
    let activeSlotID: String?
    let contentWidth: Int
    let scrollOffset: Int
    let slotFrames: [LayoutFrameSignature]

    init(layout: LayoutPlan, workspaceID: String, activeSlotID: String?) {
        self.workspaceID = workspaceID
        self.activeSlotID = activeSlotID
        self.contentWidth = Int(layout.contentWidth.rounded())
        self.scrollOffset = Int(layout.scrollOffset.rounded())
        self.slotFrames = layout.slotLayouts.map {
            LayoutFrameSignature(
                slotID: $0.slotID,
                x: Int($0.frame.x.rounded()),
                y: Int($0.frame.y.rounded()),
                width: Int($0.frame.width.rounded()),
                height: Int($0.frame.height.rounded())
            )
        }
    }
}

private struct LayoutFrameSignature: Hashable {
    let slotID: String
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

private func slotTintColor(for slot: Slot) -> Color {
    switch slot.label.lowercased() {
    case "editor":
        return Color(red: 0.16, green: 0.56, blue: 0.98)
    case "zed":
        return Color(red: 0.34, green: 0.82, blue: 0.76)
    case "zen":
        return Color(red: 0.91, green: 0.56, blue: 0.20)
    case "tether":
        return ChromeTheme.accent
    default:
        return Color.white.opacity(0.4)
    }
}

private extension LayoutPlan {
    func slotLayout(for slotID: String) -> SlotLayout? {
        slotLayouts.first(where: { $0.slotID == slotID })
    }
}

private struct ScreenSpaceFrameReporter: NSViewRepresentable {
    let onChange: (CGRect) -> Void
    let onWindowChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> ReporterView {
        let view = ReporterView()
        view.onChange = onChange
        view.onWindowChange = onWindowChange
        return view
    }

    func updateNSView(_ nsView: ReporterView, context: Context) {
        nsView.onChange = onChange
        nsView.onWindowChange = onWindowChange
        nsView.reportFrameIfNeeded()
    }
}

private struct ChromeBackdrop: View {
    var body: some View {
        ChromeTheme.chromeOcclusion
            .overlay {
                TranslucentChromeBackground()
                    .overlay(ChromeTheme.chromeBackground)
            }
    }
}

private struct NotchChromeBackground: View {
    var body: some View {
        ChromeTheme.chromeOcclusion
            .overlay {
                TranslucentChromeBackground()
                    .overlay(ChromeTheme.chromeBackground)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(ChromeTheme.border, lineWidth: 0.5)
            )
    }
}

final class ReporterView: NSView {
    var onChange: ((CGRect) -> Void)?
    var onWindowChange: ((NSWindow?) -> Void)?
    private var lastReportedFrame: CGRect = .null
    private var observationTokens: [NSObjectProtocol] = []

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        onWindowChange?(newWindow)
        if newWindow == nil {
            tearDownObservers()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
        setUpObservers()
        reportFrameIfNeeded()
    }

    override func layout() {
        super.layout()
        reportFrameIfNeeded()
    }

    func reportFrameIfNeeded() {
        guard let window else { return }
        let rectInWindow = convert(bounds, to: nil)
        let rectOnScreen = window.convertToScreen(rectInWindow)
        guard rectOnScreen.integral != lastReportedFrame.integral else { return }
        lastReportedFrame = rectOnScreen
        DispatchQueue.main.async { [onChange, rectOnScreen] in
            onChange?(rectOnScreen)
        }
    }

    private func setUpObservers() {
        tearDownObservers()

        guard let window else { return }
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didMoveNotification,
            NSWindow.didResizeNotification,
            NSWindow.didChangeScreenNotification,
            NSWindow.didEndLiveResizeNotification,
        ]

        observationTokens = names.map { name in
            center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.reportFrameIfNeeded()
                }
            }
        }
    }

    private func tearDownObservers() {
        let center = NotificationCenter.default
        observationTokens.forEach(center.removeObserver)
        observationTokens.removeAll()
    }
}

private struct StripIndicatorView: View {
    let layout: LayoutPlan
    let viewportWidth: Double
    let showThumb: Bool

    var body: some View {
        GeometryReader { proxy in
            let trackWidth = Double(proxy.size.width)
            let thumbWidth = StripIndicatorMetrics.thumbWidth(
                trackWidth: trackWidth,
                contentWidth: layout.contentWidth,
                viewportWidth: viewportWidth
            )
            let xOffset = StripIndicatorMetrics.offsetRatio(
                scrollOffset: layout.scrollOffset,
                contentWidth: layout.contentWidth,
                viewportWidth: viewportWidth
            ) * max(trackWidth - thumbWidth, 0)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 2)
                if showThumb {
                    Capsule()
                        .fill(ChromeTheme.accent.opacity(0.6))
                        .frame(width: thumbWidth, height: 2)
                        .offset(x: xOffset)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: ChromeMetrics.stripIndicatorHeight)
    }
}

enum StripIndicatorMetrics {
    static func thumbWidth(trackWidth: Double, contentWidth: Double, viewportWidth: Double) -> Double {
        guard trackWidth > 0 else { return 0 }
        guard contentWidth > 0, viewportWidth > 0 else { return trackWidth }

        let ratio = min(1, viewportWidth / max(contentWidth, viewportWidth))
        let scaledWidth = trackWidth * ratio
        return min(trackWidth, max(12, scaledWidth))
    }

    static func offsetRatio(scrollOffset: Double, contentWidth: Double, viewportWidth: Double) -> Double {
        guard contentWidth > viewportWidth, viewportWidth > 0 else { return 0 }
        let maxOffset = max(contentWidth - viewportWidth, 1)
        return min(max(scrollOffset / maxOffset, 0), 1)
    }
}

public struct DiagnosticsPanelView: View {
    let snapshot: DiagnosticsSnapshot
    let onRefresh: () -> Void

    public init(snapshot: DiagnosticsSnapshot, onRefresh: @escaping () -> Void) {
        self.snapshot = snapshot
        self.onRefresh = onRefresh
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Diagnostics")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Refresh", action: onRefresh)
            }

            GroupBox("Permissions") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(snapshot.permissions) { permission in
                        HStack {
                            Text(permission.kind.rawValue)
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            Text(permission.state.rawValue)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(ChromeTheme.textSecondary)
                        }
                        Text(permission.detail)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(ChromeTheme.textSecondary)
                    }
                }
            }

            GroupBox("Build Identity") {
                VStack(alignment: .leading, spacing: 6) {
                    DiagnosticRow(label: "Signing", value: snapshot.buildIdentity.signingMode.rawValue)
                    DiagnosticRow(label: "Identity", value: snapshot.buildIdentity.signingIdentityLabel ?? "unknown")
                    DiagnosticRow(label: "Bundle ID", value: snapshot.buildIdentity.bundleIdentifier.isEmpty ? "unknown" : snapshot.buildIdentity.bundleIdentifier)
                    DiagnosticRow(label: "Bundle Path", value: snapshot.buildIdentity.bundlePath.isEmpty ? "unknown" : snapshot.buildIdentity.bundlePath)
                    DiagnosticRow(label: "Expected Path", value: snapshot.buildIdentity.expectedInstallPath ?? "unknown")
                    DiagnosticRow(label: "Launch Path", value: snapshot.buildIdentity.launchedFromExpectedPath ? "matches expected install path" : "does not match expected install path")

                    if let buildTimestamp = snapshot.buildIdentity.buildTimestamp {
                        DiagnosticRow(
                            label: "Built",
                            value: buildTimestamp.formatted(date: .abbreviated, time: .standard)
                        )
                    }
                }
            }

            GroupBox("Adapters") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(snapshot.adapterHealth) { report in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(report.adapterID)
                                .font(.system(size: 11, weight: .medium))
                            Text(report.detail)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(ChromeTheme.textSecondary)
                        }
                    }
                }
            }

            GroupBox("Windows") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(snapshot.windows.prefix(12)) { window in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(window.appName)
                                    .font(.system(size: 11, weight: .medium))
                                Text(window.windowTitle)
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(ChromeTheme.textSecondary)
                            }
                        }
                    }
                }
                .frame(maxHeight: 180)
            }

            GroupBox("Paths") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(snapshot.stateDirectory)
                    Text(snapshot.logDirectory)
                }
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(ChromeTheme.textSecondary)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 460, height: 560)
    }
}

private struct DiagnosticRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
            Text(value)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(ChromeTheme.textSecondary)
                .textSelection(.enabled)
        }
    }
}

@MainActor
public final class DiagnosticsPanelController {
    private var panel: NSPanel?
    private var refreshAction: (() -> Void)?

    public init() {}

    public func show(snapshot: DiagnosticsSnapshot, onRefresh: @escaping () -> Void) {
        refreshAction = onRefresh

        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
                styleMask: [.titled, .closable, .utilityWindow, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.title = "Nexus Diagnostics"
            panel.isFloatingPanel = true
            panel.level = .floating
            self.panel = panel
        }

        update(snapshot: snapshot)
        panel?.center()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func update(snapshot: DiagnosticsSnapshot) {
        panel?.contentView = NSHostingView(
            rootView: DiagnosticsPanelView(snapshot: snapshot) { [weak self] in
                self?.refreshAction?()
            }
        )
    }
}
