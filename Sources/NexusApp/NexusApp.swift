import SwiftUI
import StageChrome

@main
struct NexusApplication: App {
    @NSApplicationDelegateAdaptor(NexusAppDelegate.self) private var appDelegate
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            StageChromeView(
                session: environment.session,
                layoutEngine: environment.layoutEngine,
                workspaceTemplateOptions: environment.workspaceTemplateOptions,
                diagnosticsSnapshot: environment.diagnosticsSnapshot,
                shellPresentationMode: environment.shellPresentationMode,
                shellDisplayLayout: environment.shellDisplayLayout,
                onCreateWorkspace: environment.createWorkspace,
                onAddFocusedWindow: {
                    Task {
                        await environment.addFocusedWindowToSelectedWorkspace()
                    }
                },
                onRemoveSelectedSlot: environment.session.removeSelectedSlot,
                onToggleAutoAdd: environment.toggleSelectedWorkspaceAutoAdd,
                onOpenDiagnostics: environment.openDiagnosticsPanel,
                onRequestAccessibility: {
                    Task {
                        await environment.requestAccessibilityAccess()
                    }
                },
                onRefreshDiagnostics: {
                    Task {
                        await environment.refreshDiagnostics()
                    }
                },
                onRevealAll: environment.revealAll,
                onLayoutDidUpdate: environment.applyChoreography,
                onStageViewportFrameChanged: environment.updateStageViewportFrame,
                onShellWindowChanged: environment.updateShellWindow
            )
            .task {
                await environment.start()
            }
        }
        .defaultSize(width: 1440, height: 900)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("Workspace") {
                Button("Next Workspace") {
                    environment.session.selectNextWorkspace()
                }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])

                Button("Previous Workspace") {
                    environment.session.selectPreviousWorkspace()
                }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])

                Divider()

                ForEach(environment.workspaceTemplateOptions) { option in
                    Button("New \(option.title)") {
                        environment.createWorkspace(from: option.id)
                    }
                }

                Divider()

                Button(environment.session.selectedWorkspace?.autoAddPolicy == .focusedStandardWindow ? "Disable Auto-add" : "Enable Auto-add") {
                    environment.toggleSelectedWorkspaceAutoAdd()
                }

                ForEach(Array(environment.session.workspaces.prefix(9).enumerated()), id: \.element.id) { index, workspace in
                    Button(workspace.name) {
                        environment.session.selectWorkspace(at: index)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command])
                }
            }

            CommandMenu("Slots") {
                Button("Add Focused Window") {
                    Task {
                        await environment.addFocusedWindowToSelectedWorkspace()
                    }
                }

                Button("Remove Selected Slot") {
                    environment.session.removeSelectedSlot()
                }

                Divider()

                Button("Move Slot Left") {
                    _ = environment.session.moveSelectedSlotLeft()
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option, .shift])

                Button("Move Slot Right") {
                    _ = environment.session.moveSelectedSlotRight()
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option, .shift])

                Divider()

                Button("Next Slot") {
                    environment.session.selectNextSlot()
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])

                Button("Previous Slot") {
                    environment.session.selectPreviousSlot()
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            }

            CommandMenu("Nexus") {
                Button("Open Diagnostics") {
                    environment.openDiagnosticsPanel()
                }
                .keyboardShortcut("d", modifiers: [.command, .option])

                Button("Reveal All") {
                    environment.revealAll()
                }
                .keyboardShortcut("r", modifiers: [.command, .option, .shift])

                Button(environment.shellPresentationMenuTitle()) {
                    environment.toggleShellPresentationMode()
                }
                .keyboardShortcut("f", modifiers: [.command, .option, .shift])
            }
        }
    }
}
