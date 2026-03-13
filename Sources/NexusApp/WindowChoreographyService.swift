import AppKit
import Foundation
import OSLog
import SharedTypes
import VisibilityEngine
import WindowRegistry

@MainActor
final class WindowChoreographyService {
    private let windowRegistry: AXWindowRegistry
    private let visibilityCoordinator: VisibilityCoordinator

    private let logger = Logger(subsystem: "dev.nexusniri.Nexus", category: "choreography")

    init(
        windowRegistry: AXWindowRegistry,
        visibilityCoordinator: VisibilityCoordinator
    ) {
        self.windowRegistry = windowRegistry
        self.visibilityCoordinator = visibilityCoordinator
    }

    func apply(
        workspace: Workspace,
        previousWorkspace: Workspace?,
        layout: LayoutPlan
    ) async {
        do {
            let snapshot = try await windowRegistry.snapshot()
            let actions = try await visibilityCoordinator.transition(
                from: previousWorkspace,
                to: workspace,
                layout: layout,
                windows: snapshot.windows
            )
            await apply(
                actions: actions,
                currentWorkspace: workspace,
                previousWorkspace: previousWorkspace,
                windows: snapshot.windows
            )
        } catch {
            logger.error("Failed to apply window choreography for workspace \(workspace.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func revealAll(currentWorkspace: Workspace?, previousWorkspace: Workspace?) async {
        do {
            try await visibilityCoordinator.panicRevealAll()
            let snapshot = try await windowRegistry.snapshot()
            let actions = await visibilityCoordinator.currentActions()
            await apply(
                actions: actions,
                currentWorkspace: currentWorkspace,
                previousWorkspace: previousWorkspace,
                windows: snapshot.windows
            )
        } catch {
            logger.error("Failed to reveal all windows: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func apply(
        actions: [VisibilityAction],
        currentWorkspace: Workspace?,
        previousWorkspace: Workspace?,
        windows: [WindowCandidate]
    ) async {
        for action in actions {
            guard let slot = slot(
                withID: action.slotID,
                currentWorkspace: currentWorkspace,
                previousWorkspace: previousWorkspace
            ) else {
                logger.debug("Skipping action for unknown slot \(action.slotID, privacy: .public).")
                continue
            }

            let candidate = resolveCandidate(for: slot, action: action, windows: windows)
            await apply(
                action: action,
                slot: slot,
                candidate: candidate,
                activeSlotID: currentWorkspace?.activeSlotID
            )
        }
    }

    private func apply(
        action: VisibilityAction,
        slot: Slot,
        candidate: WindowCandidate?,
        activeSlotID: String?
    ) async {
        switch action.kind {
        case .show, .reveal:
            await stageVisibleWindow(
                slot: slot,
                action: action,
                candidate: candidate,
                shouldFocus: slot.id == activeSlotID || action.kind == .reveal
            )
        case .park:
            await parkWindow(slot: slot, action: action, candidate: candidate)
        case .minimize:
            if let candidate {
                do {
                    try await windowRegistry.setWindowMinimized(
                        processID: candidate.processID,
                        windowID: candidate.windowID,
                        to: true
                    )
                } catch {
                    logger.debug("Unable to minimize window for slot \(slot.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        case .hideApp:
            if let candidate {
                do {
                    try await windowRegistry.setApplicationHidden(processID: candidate.processID, to: true)
                } catch {
                    logger.debug("Unable to hide app for slot \(slot.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        case .detach:
            logger.notice("Detach requested for slot \(slot.id, privacy: .public); leaving window unmanaged.")
        }
    }

    private func stageVisibleWindow(
        slot: Slot,
        action: VisibilityAction,
        candidate: WindowCandidate?,
        shouldFocus: Bool
    ) async {
        if let candidate {
            do {
                try await windowRegistry.setApplicationHidden(processID: candidate.processID, to: false)
                try await windowRegistry.setWindowMinimized(
                    processID: candidate.processID,
                    windowID: candidate.windowID,
                    to: false
                )
                if let targetFrame = action.targetFrame {
                    try await windowRegistry.setWindowFrame(
                        processID: candidate.processID,
                        windowID: candidate.windowID,
                        to: targetFrame
                    )
                }
                if shouldFocus {
                    try await windowRegistry.raiseWindow(processID: candidate.processID, windowID: candidate.windowID)
                }
                return
            } catch {
                logger.debug("Window staging fallback engaged for slot \(slot.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        do {
            try openTarget(for: slot)
        } catch {
            logger.debug("Unable to open target for slot \(slot.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func parkWindow(
        slot: Slot,
        action: VisibilityAction,
        candidate: WindowCandidate?
    ) async {
        if let candidate, let targetFrame = action.targetFrame {
            do {
                try await windowRegistry.setApplicationHidden(processID: candidate.processID, to: false)
                try await windowRegistry.setWindowMinimized(
                    processID: candidate.processID,
                    windowID: candidate.windowID,
                    to: false
                )
                try await windowRegistry.setWindowFrame(
                    processID: candidate.processID,
                    windowID: candidate.windowID,
                    to: targetFrame
                )
                return
            } catch {
                logger.debug("Unable to park window for slot \(slot.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        if let candidate {
            do {
                try await windowRegistry.setWindowMinimized(
                    processID: candidate.processID,
                    windowID: candidate.windowID,
                    to: true
                )
                return
            } catch {
                logger.debug("Unable to minimize parked window for slot \(slot.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func slot(
        withID slotID: String,
        currentWorkspace: Workspace?,
        previousWorkspace: Workspace?
    ) -> Slot? {
        currentWorkspace?.slots.first(where: { $0.id == slotID })
            ?? previousWorkspace?.slots.first(where: { $0.id == slotID })
    }

    private func resolveCandidate(
        for slot: Slot,
        action: VisibilityAction,
        windows: [WindowCandidate]
    ) -> WindowCandidate? {
        let bundleID = slot.appBinding?.bundleID
        let titleHints = slot.appBinding?.titleHints ?? []

        if let windowID = action.windowID,
           let exactMatch = windows.first(where: { $0.windowID == windowID && (bundleID == nil || $0.bundleID == bundleID) }) {
            return exactMatch
        }

        let candidates = windows.filter { candidate in
            if let bundleID {
                return candidate.bundleID == bundleID
            }
            return true
        }

        return candidates.max { lhs, rhs in
            candidateScore(lhs, slot: slot, titleHints: titleHints) < candidateScore(rhs, slot: slot, titleHints: titleHints)
        }
    }

    private func candidateScore(
        _ candidate: WindowCandidate,
        slot: Slot,
        titleHints: [String]
    ) -> Int {
        var score = 0

        if candidate.source == .accessibility {
            score += 3
        }
        if candidate.isFocused {
            score += 2
        }
        if slot.runtimeBinding?.windowID == candidate.windowID {
            score += 6
        }
        if slot.runtimeBinding?.processID == candidate.processID {
            score += 4
        }
        if titleHints.contains(where: { candidate.windowTitle.localizedCaseInsensitiveContains($0) }) {
            score += 5
        }

        return score
    }

    private func openTarget(for slot: Slot) throws {
        guard let bundleID = slot.appBinding?.bundleID else {
            throw NexusError.invalidState("No bundle identifier is configured for \(slot.label).")
        }

        if let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            runningApp.activate()
            return
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw NexusError.notFound("No installed app found for bundle ID \(bundleID).")
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            if let error {
                self.logger.debug("Open application callback failed for slot \(slot.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
