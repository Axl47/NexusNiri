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
    private let onOpenDiagnostics: () -> Void
    private let onRefreshDiagnostics: () -> Void
    private let onRevealAll: () -> Void
    private let onLayoutDidUpdate: (Workspace, LayoutPlan) async -> Void

    public init(
        session: WorkspaceSession,
        layoutEngine: any LayoutComputing,
        diagnosticsSnapshot: DiagnosticsSnapshot,
        onOpenDiagnostics: @escaping () -> Void,
        onRefreshDiagnostics: @escaping () -> Void,
        onRevealAll: @escaping () -> Void,
        onLayoutDidUpdate: @escaping (Workspace, LayoutPlan) async -> Void
    ) {
        self.session = session
        self.layoutEngine = layoutEngine
        self.diagnosticsSnapshot = diagnosticsSnapshot
        self.onOpenDiagnostics = onOpenDiagnostics
        self.onRefreshDiagnostics = onRefreshDiagnostics
        self.onRevealAll = onRevealAll
        self.onLayoutDidUpdate = onLayoutDidUpdate
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                topbar
                Divider().overlay(ChromeTheme.border)
                viewport
            }
        }
        .frame(minWidth: 1120, minHeight: 760)
        .background(ChromeTheme.windowBackground)
    }

    private var sidebar: some View {
        ZStack(alignment: .leading) {
            TranslucentChromeBackground()
                .overlay(ChromeTheme.chromeBackground)

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
            TranslucentChromeBackground()
                .overlay(ChromeTheme.chromeBackground)

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

                if let status = diagnosticsSnapshot.permissions.first(where: { $0.kind == .accessibility && $0.state != .granted }) {
                    Button(status.kind == .accessibility ? "Enable Accessibility" : "Permissions") {
                        openSettings(for: status)
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

    private var viewport: some View {
        GeometryReader { proxy in
            let geometry = ChromeMetrics.stageGeometry(for: proxy.size)
            let workspace = session.selectedWorkspace
            let layout = workspace.map { layoutEngine.planLayout(for: $0, in: geometry) }

            ZStack(alignment: .bottom) {
                Color.clear

                if let workspace, let layout {
                    StageStripView(
                        session: session,
                        workspace: workspace,
                        layout: layout,
                        stageWidth: geometry.stageWidth,
                        onLayoutDidUpdate: onLayoutDidUpdate
                    )
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
        let index = min(workspace.slotOrder.count, session.selectedSlotIndex + 1)
        return count == 1 ? "1 app" : "\(count) apps · \(index) / \(count)"
    }

    private func openSettings(for status: PermissionStatus) {
        guard let settingsURL = status.settingsURL, let url = URL(string: settingsURL) else { return }
        NSWorkspace.shared.open(url)
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

private struct StageStripView: View {
    @Bindable var session: WorkspaceSession
    let workspace: Workspace
    let layout: LayoutPlan
    let stageWidth: Double
    let onLayoutDidUpdate: (Workspace, LayoutPlan) async -> Void

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: ChromeMetrics.slotGap) {
                        ForEach(workspace.orderedSlots) { slot in
                            let slotLayout = layout.slotLayouts.first(where: { $0.slotID == slot.id })
                            SlotCard(
                                slot: slot,
                                width: slotLayout?.frame.width ?? 420,
                                isFocused: workspace.activeSlotID == slot.id,
                                onResize: { width, persist in
                                    session.resizeSlot(
                                        id: slot.id,
                                        to: width,
                                        viewportWidth: stageWidth,
                                        persist: persist
                                    )
                                }
                            )
                            .id(slot.id)
                            .onTapGesture {
                                session.selectSlot(id: slot.id)
                            }
                        }
                    }
                    .padding(.horizontal, 0)
                    .padding(.vertical, 0)
                }
                .task(id: LayoutTaskKey(layout: layout, workspaceID: workspace.id, activeSlotID: workspace.activeSlotID)) {
                    session.updateVisibility(using: layout)
                    await onLayoutDidUpdate(workspace, layout)
                    guard let activeSlotID = workspace.activeSlotID else { return }
                    withAnimation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.4)) {
                        proxy.scrollTo(activeSlotID, anchor: .center)
                    }
                }

                StripIndicatorView(layout: layout)
                    .padding(.top, 10)
                    .padding(.horizontal, 18)
                    .opacity(workspace.slotOrder.count == 1 ? 0 : 1)
            }
            .padding(.top, 0)
            .padding(.bottom, 10)
        }
    }
}

private struct SlotCard: View {
    let slot: Slot
    let width: Double
    let isFocused: Bool
    let onResize: (Double, Bool) -> Void

    @State private var dragWidth: Double?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(appColor)
                    .frame(width: 14, height: 14)
                    .overlay {
                        Text(String(slot.label.prefix(1)).uppercased())
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.white)
                    }

                Text(slot.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ChromeTheme.textSecondary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: ChromeMetrics.slotHeaderHeight)
            .background(ChromeTheme.surface.opacity(0.8))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(ChromeTheme.border)
                    .frame(height: 0.5)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(slot.appBinding?.bundleID ?? "Unbound slot")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(ChromeTheme.textTertiary)

                Text(slot.layoutRole.rawValue.capitalized)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(ChromeTheme.textPrimary)

                Text(slot.kind.rawValue)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(ChromeTheme.textSecondary)

                Spacer(minLength: 0)

                if slot.adapterID == "tether" {
                    Text("First-class adapter target")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ChromeTheme.accent)
                } else {
                    Text("Generic staged app")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ChromeTheme.textSecondary)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 0).fill(Color.white.opacity(0.025)))
        }
        .frame(width: dragWidth ?? width)
        .frame(maxHeight: .infinity)
        .opacity(isFocused ? 1.0 : 0.5)
        .animation(.easeOut(duration: 0.3), value: isFocused)
        .overlay(alignment: .trailing) {
            ResizeHandle(isActive: isFocused)
                .padding(.vertical, 20)
                .gesture(resizeGesture)
        }
    }

    private var appColor: Color {
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

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let proposedWidth = max(260, width + value.translation.width)
                dragWidth = proposedWidth
                onResize(proposedWidth, false)
            }
            .onEnded { value in
                let proposedWidth = max(260, width + value.translation.width)
                dragWidth = nil
                onResize(proposedWidth, true)
            }
    }
}

private struct ResizeHandle: View {
    let isActive: Bool

    var body: some View {
        ZStack {
            Capsule()
                .fill(ChromeTheme.border)
                .frame(width: 1)

            RoundedRectangle(cornerRadius: 4)
                .fill(isActive ? ChromeTheme.accent.opacity(0.9) : ChromeTheme.surfaceHover)
                .frame(width: 8, height: 56)
                .overlay {
                    VStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { _ in
                            Capsule()
                                .fill(Color.white.opacity(0.7))
                                .frame(width: 2, height: 8)
                        }
                    }
                }
        }
        .frame(width: 12)
        .contentShape(Rectangle())
    }
}

private struct LayoutTaskKey: Hashable {
    let workspaceID: String
    let activeSlotID: String?
    let contentWidth: Int
    let slotWidths: [Int]

    init(layout: LayoutPlan, workspaceID: String, activeSlotID: String?) {
        self.workspaceID = workspaceID
        self.activeSlotID = activeSlotID
        self.contentWidth = Int(layout.contentWidth.rounded())
        self.slotWidths = layout.slotLayouts.map { Int($0.frame.width.rounded()) }
    }
}

private struct StripIndicatorView: View {
    let layout: LayoutPlan

    var body: some View {
        GeometryReader { proxy in
            let trackWidth = proxy.size.width
            let thumbWidth = max(12, trackWidth * CGFloat(thumbRatio))
            let xOffset = (trackWidth - thumbWidth) * CGFloat(offsetRatio)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 2)
                Capsule()
                    .fill(ChromeTheme.accent.opacity(0.6))
                    .frame(width: thumbWidth, height: 2)
                    .offset(x: xOffset)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: ChromeMetrics.stripIndicatorHeight)
    }

    private var thumbRatio: Double {
        guard layout.contentWidth > 0 else { return 1 }
        return min(1, 1 / max(1, layout.contentWidth / 1200))
    }

    private var offsetRatio: Double {
        let maxOffset = max(layout.contentWidth - 1200, 1)
        return min(max(layout.scrollOffset / maxOffset, 0), 1)
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
