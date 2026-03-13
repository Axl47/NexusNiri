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
                diagnosticsSnapshot: environment.diagnosticsSnapshot,
                onOpenDiagnostics: environment.openDiagnosticsPanel,
                onRefreshDiagnostics: {
                    Task {
                        await environment.refreshDiagnostics()
                    }
                },
                onRevealAll: environment.revealAll,
                onLayoutDidUpdate: environment.applyChoreography
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

                ForEach(Array(environment.session.workspaces.prefix(9).enumerated()), id: \.element.id) { index, workspace in
                    Button(workspace.name) {
                        environment.session.selectWorkspace(at: index)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command])
                }
            }

            CommandMenu("Slots") {
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
            }
        }
    }
}
