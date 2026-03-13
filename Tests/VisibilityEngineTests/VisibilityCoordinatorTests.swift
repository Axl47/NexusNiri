import Testing
import SharedTypes
@testable import VisibilityEngine

@Test
func transitionStagesVisibleSlotsAndParksOutgoingWorkspaceSlots() async throws {
    let previousSlots = [
        Slot(id: "editor", workspaceID: "w1", kind: .externalWindow, label: "Editor", appBinding: AppBinding(bundleID: "com.example.editor"), widthPolicy: SizePolicy(mode: .fraction, value: 0.5), layoutRole: .primary),
        Slot(id: "browser", workspaceID: "w1", kind: .externalWindow, label: "Browser", appBinding: AppBinding(bundleID: "com.example.browser"), widthPolicy: SizePolicy(mode: .fraction, value: 0.5), layoutRole: .secondary),
    ]
    let nextSlots = [
        Slot(id: "zed", workspaceID: "w2", kind: .externalWindow, label: "Zed", appBinding: AppBinding(bundleID: "dev.zed.Zed"), widthPolicy: SizePolicy(mode: .fraction, value: 0.6), layoutRole: .primary),
        Slot(id: "docs", workspaceID: "w2", kind: .externalWindow, label: "Docs", appBinding: AppBinding(bundleID: "app.zen-browser.zen"), widthPolicy: SizePolicy(mode: .fraction, value: 0.4), layoutRole: .secondary),
    ]

    let previousWorkspace = Workspace(
        id: "w1",
        name: "Previous",
        activeSlotID: "editor",
        slotOrder: previousSlots.map(\.id),
        slots: previousSlots
    )
    let nextWorkspace = Workspace(
        id: "w2",
        name: "Next",
        activeSlotID: "zed",
        slotOrder: nextSlots.map(\.id),
        slots: nextSlots
    )
    let layout = LayoutPlan(
        slotLayouts: [
            SlotLayout(slotID: "zed", frame: RectValue(x: 0, y: 0, width: 720, height: 700), isFocused: true),
            SlotLayout(slotID: "docs", frame: RectValue(x: 722, y: 0, width: 480, height: 700), isFocused: false),
        ],
        contentWidth: 1202,
        scrollOffset: 0,
        visibleSlotIDs: ["zed"],
        parkedSlotIDs: ["docs"],
        activeSlotIndex: 0
    )
    let windows = [
        WindowCandidate(bundleID: "dev.zed.Zed", appName: "Zed", windowTitle: "Nexus", processID: 100, windowID: 1, frame: .zero, source: .accessibility),
        WindowCandidate(bundleID: "app.zen-browser.zen", appName: "Zen", windowTitle: "Docs", processID: 101, windowID: 2, frame: .zero, source: .accessibility),
    ]
    let coordinator = VisibilityCoordinator()

    let actions = try await coordinator.transition(
        from: previousWorkspace,
        to: nextWorkspace,
        layout: layout,
        windows: windows
    )

    let zedAction = actions.first(where: { $0.slotID == "zed" })
    let docsAction = actions.first(where: { $0.slotID == "docs" })
    let editorAction = actions.first(where: { $0.slotID == "editor" })
    let browserAction = actions.first(where: { $0.slotID == "browser" })

    #expect(zedAction?.kind == .show)
    #expect(zedAction?.windowID == nil)
    #expect(docsAction?.kind == .park)
    #expect(docsAction?.windowID == nil)
    #expect(editorAction?.kind == .park)
    #expect(browserAction?.kind == .park)
}

@Test
func transitionStagesEveryVisibleSlotAndOnlyParksOffstageSlots() async throws {
    let slots = [
        Slot(id: "editor", workspaceID: "w", kind: .externalWindow, label: "Editor", appBinding: AppBinding(bundleID: "com.example.editor"), widthPolicy: SizePolicy(mode: .fraction, value: 0.55), layoutRole: .primary),
        Slot(id: "browser", workspaceID: "w", kind: .externalWindow, label: "Browser", appBinding: AppBinding(bundleID: "com.example.browser"), widthPolicy: SizePolicy(mode: .fraction, value: 0.45), layoutRole: .secondary),
    ]
    let workspace = Workspace(
        id: "w",
        name: "Main",
        activeSlotID: "browser",
        slotOrder: slots.map(\.id),
        slots: slots
    )
    let layout = LayoutPlan(
        slotLayouts: [
            SlotLayout(slotID: "editor", frame: RectValue(x: 0, y: 0, width: 760, height: 700), isFocused: false),
            SlotLayout(slotID: "browser", frame: RectValue(x: 762, y: 0, width: 620, height: 700), isFocused: true),
        ],
        contentWidth: 1382,
        scrollOffset: 120,
        visibleSlotIDs: ["editor", "browser"],
        parkedSlotIDs: [],
        activeSlotIndex: 1
    )
    let windows = [
        WindowCandidate(bundleID: "com.example.editor", appName: "Editor", windowTitle: "Project", processID: 300, windowID: 30, frame: .zero, source: .accessibility),
        WindowCandidate(bundleID: "com.example.browser", appName: "Browser", windowTitle: "Docs", processID: 301, windowID: 31, frame: .zero, source: .accessibility),
    ]
    let coordinator = VisibilityCoordinator()

    let actions = try await coordinator.transition(from: nil, to: workspace, layout: layout, windows: windows)
    let editorAction = actions.first(where: { $0.slotID == "editor" })
    let browserAction = actions.first(where: { $0.slotID == "browser" })

    #expect(editorAction?.kind == .show)
    #expect(browserAction?.kind == .show)
}

@Test
func transitionLeavesWindowIDUnsetWhenNoRuntimeBindingExists() async throws {
    let slots = [
        Slot(
            id: "editor",
            workspaceID: "w",
            kind: .externalWindow,
            label: "Editor",
            appBinding: AppBinding(bundleID: "com.example.editor"),
            widthPolicy: SizePolicy(mode: .fraction, value: 0.55),
            layoutRole: .primary
        ),
    ]
    let workspace = Workspace(
        id: "w",
        name: "Main",
        activeSlotID: "editor",
        slotOrder: ["editor"],
        slots: slots
    )
    let layout = LayoutPlan(
        slotLayouts: [
            SlotLayout(slotID: "editor", frame: RectValue(x: 0, y: 0, width: 760, height: 700), isFocused: true),
        ],
        contentWidth: 760,
        scrollOffset: 0,
        visibleSlotIDs: ["editor"],
        parkedSlotIDs: [],
        activeSlotIndex: 0
    )
    let windows = [
        WindowCandidate(bundleID: "com.example.editor", appName: "Editor", windowTitle: "Project A", processID: 300, windowID: 30, frame: .zero, source: .accessibility),
        WindowCandidate(bundleID: "com.example.editor", appName: "Editor", windowTitle: "Project B", processID: 300, windowID: 31, frame: .zero, source: .accessibility),
    ]
    let coordinator = VisibilityCoordinator()

    let actions = try await coordinator.transition(from: nil, to: workspace, layout: layout, windows: windows)

    #expect(actions.first?.kind == .show)
    #expect(actions.first?.windowID == nil)
}

@Test
func panicRevealAllRewritesLastPlannedActionsAndNextTransitionResumesNormally() async throws {
    let slots = [
        Slot(id: "editor", workspaceID: "w", kind: .externalWindow, label: "Editor", appBinding: AppBinding(bundleID: "com.example.editor"), widthPolicy: SizePolicy(mode: .fraction, value: 0.6), layoutRole: .primary),
        Slot(id: "browser", workspaceID: "w", kind: .externalWindow, label: "Browser", appBinding: AppBinding(bundleID: "com.example.browser"), widthPolicy: SizePolicy(mode: .fraction, value: 0.4), layoutRole: .secondary),
    ]
    let workspace = Workspace(
        id: "w",
        name: "Main",
        activeSlotID: "editor",
        slotOrder: slots.map(\.id),
        slots: slots
    )
    let layout = LayoutPlan(
        slotLayouts: [
            SlotLayout(slotID: "editor", frame: RectValue(x: 0, y: 0, width: 800, height: 700), isFocused: true),
            SlotLayout(slotID: "browser", frame: RectValue(x: 802, y: 0, width: 400, height: 700), isFocused: false),
        ],
        contentWidth: 1202,
        scrollOffset: 0,
        visibleSlotIDs: ["editor"],
        parkedSlotIDs: ["browser"],
        activeSlotIndex: 0
    )
    let windows = [
        WindowCandidate(bundleID: "com.example.editor", appName: "Editor", windowTitle: "Project", processID: 200, windowID: 20, frame: .zero, source: .accessibility),
        WindowCandidate(bundleID: "com.example.browser", appName: "Browser", windowTitle: "Docs", processID: 201, windowID: 21, frame: .zero, source: .accessibility),
    ]
    let coordinator = VisibilityCoordinator()

    _ = try await coordinator.transition(from: nil, to: workspace, layout: layout, windows: windows)
    try await coordinator.panicRevealAll()
    let revealActions = await coordinator.currentActions()
    let resumedActions = try await coordinator.transition(from: nil, to: workspace, layout: layout, windows: windows)
    let resumedEditorAction = resumedActions.first(where: { $0.slotID == "editor" })
    let resumedBrowserAction = resumedActions.first(where: { $0.slotID == "browser" })

    #expect(revealActions.allSatisfy { $0.kind == .reveal })
    #expect(resumedEditorAction?.kind == .show)
    #expect(resumedBrowserAction?.kind == .park)
}
