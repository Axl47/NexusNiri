import Foundation
import SharedTypes
import Testing
import WorkspaceEngine
@testable import NexusApp

@MainActor
@Test
func workspaceTemplateCatalogInstantiatesStarterWorkspaceFromPresets() {
    let catalog = WorkspaceTemplateCatalog()

    let workspace = catalog.instantiate(templateID: "starter", workspaceName: "Fresh")

    #expect(workspace?.name == "Fresh")
    #expect(workspace?.slotOrder.count == 3)
    #expect(workspace?.slots.first?.targetingMode == .application)
    #expect(workspace?.slots.last?.adapterID == "tether")
}

@MainActor
@Test
func focusedWindowSlotFactoryCreatesWindowTargetedSlotUsingPresetDefaults() {
    let factory = FocusedWindowSlotFactory()
    let slot = factory.makeSlot(
        from: WindowCandidate(
            bundleID: "com.t3tools.tether",
            appName: "Tether",
            windowTitle: "Tether - Docs",
            processID: 404,
            windowID: 12,
            frame: .zero,
            isFocused: true,
            source: .accessibility
        ),
        workspaceID: "workspace",
        existingLabels: []
    )

    #expect(slot?.targetingMode == .window)
    #expect(slot?.kind == .hybrid)
    #expect(slot?.adapterID == "tether")
    #expect(slot?.appBinding?.titleHints == ["Docs"])
}

@MainActor
@Test
func appEnvironmentAddsFocusedWindowToSelectedWorkspaceFromLastObservedExternalCandidate() async {
    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("NexusAppEnvironmentAddFocusedWindow-\(UUID().uuidString)", isDirectory: true)
    let store = JSONWorkspaceStore(baseDirectoryURL: tempURL)
    let registry = TestWindowRegistry()
    let environment = AppEnvironment(workspaceStore: store, windowRegistry: registry, registerDefaultAdapters: false)
    let workspace = Workspace(id: "workspace", name: "Blank", slots: [])
    await environment.session.load(seedWorkspaces: [workspace])

    await environment.handleFocusedWindowCandidate(
        WindowCandidate(
            bundleID: "com.example.browser",
            appName: "Browser",
            windowTitle: "Docs - Nexus",
            processID: 111,
            windowID: 9,
            frame: .zero,
            isFocused: true,
            source: .accessibility
        )
    )

    await environment.addFocusedWindowToSelectedWorkspace()

    #expect(environment.session.selectedWorkspace?.slotOrder.count == 1)
    #expect(environment.session.selectedWorkspace?.slots.first?.targetingMode == .window)
    #expect(environment.session.selectedWorkspace?.slots.first?.label == "Docs - Nexus")
}

@MainActor
@Test
func appEnvironmentManualAddSelectsExistingExactWindowInsteadOfDuplicating() async {
    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("NexusAppEnvironmentNoDuplicateAdd-\(UUID().uuidString)", isDirectory: true)
    let store = JSONWorkspaceStore(baseDirectoryURL: tempURL)
    let registry = TestWindowRegistry()
    let environment = AppEnvironment(workspaceStore: store, windowRegistry: registry, registerDefaultAdapters: false)
    let slot = Slot(
        id: "captured",
        workspaceID: "workspace",
        kind: .externalWindow,
        targetingMode: .window,
        label: "Docs",
        appBinding: AppBinding(bundleID: "com.example.browser", titleHints: ["Docs"]),
        widthPolicy: SizePolicy(mode: .fraction, value: 0.5),
        layoutRole: .primary,
        runtimeBinding: RuntimeBinding(processID: 111, windowID: 9, matchConfidence: 1, state: .attached)
    )
    let workspace = Workspace(
        id: "workspace",
        name: "Main",
        activeSlotID: slot.id,
        slotOrder: [slot.id],
        layoutState: LayoutState(activeIndex: 0, centeredSlotID: slot.id),
        slots: [slot]
    )
    await environment.session.load(seedWorkspaces: [workspace])

    await environment.handleFocusedWindowCandidate(
        WindowCandidate(
            bundleID: "com.example.browser",
            appName: "Browser",
            windowTitle: "Docs",
            processID: 111,
            windowID: 9,
            frame: .zero,
            isFocused: true,
            source: .accessibility
        )
    )

    await environment.addFocusedWindowToSelectedWorkspace()

    #expect(environment.session.selectedWorkspace?.slotOrder == [slot.id])
    #expect(environment.session.selectedWorkspace?.activeSlotID == slot.id)
}

@MainActor
@Test
func appEnvironmentAutoAddsFocusedWindowWhenWorkspacePolicyIsEnabled() async {
    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("NexusAppEnvironmentAutoAdd-\(UUID().uuidString)", isDirectory: true)
    let store = JSONWorkspaceStore(baseDirectoryURL: tempURL)
    let registry = TestWindowRegistry()
    let environment = AppEnvironment(workspaceStore: store, windowRegistry: registry, registerDefaultAdapters: false)
    let workspace = Workspace(id: "workspace", name: "Blank", autoAddPolicy: .focusedStandardWindow, slots: [])
    await environment.session.load(seedWorkspaces: [workspace])

    await environment.handleFocusedWindowCandidate(
        WindowCandidate(
            bundleID: "com.example.browser",
            appName: "Browser",
            windowTitle: "Roadmap",
            processID: 222,
            windowID: 13,
            frame: .zero,
            isFocused: true,
            source: .accessibility
        )
    )

    #expect(environment.session.selectedWorkspace?.slotOrder.count == 1)
    #expect(environment.session.selectedWorkspace?.slots.first?.label == "Roadmap")
    #expect(environment.session.lastSelectionOrigin == SelectionOrigin.nativeFocusSync)
}

private actor TestWindowRegistry: WindowRegistryService, WindowControlling {
    func snapshot() async throws -> WindowRegistrySnapshot {
        WindowRegistrySnapshot(isAccessibilityTrusted: true, windows: [])
    }

    func focusedWindowCandidate() async throws -> WindowCandidate? {
        nil
    }

    func setWindowFrame(processID: Int, windowID: Int?, to frame: RectValue) async throws {}
    func setWindowMinimized(processID: Int, windowID: Int?, to minimized: Bool) async throws {}
    func setApplicationHidden(processID: Int, to hidden: Bool) async throws {}
    func activateApplication(processID: Int) async throws {}
    func raiseWindow(processID: Int, windowID: Int?) async throws {}
    func focusWindow(processID: Int, windowID: Int?) async throws {}
}
