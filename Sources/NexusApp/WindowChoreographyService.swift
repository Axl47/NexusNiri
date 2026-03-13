import AppKit
import AdapterBus
import Foundation
import OSLog
import SharedTypes
import StageChrome
import VisibilityEngine
import WindowRegistry

@MainActor
protocol WindowChoreographing: Sendable {
    func apply(
        workspace: Workspace,
        previousWorkspace: Workspace?,
        layout: LayoutPlan,
        stageViewportFrame: CGRect?,
        focusPolicy: ChoreographyFocusPolicy
    ) async -> ChoreographyOutcome

    func revealAll(
        currentWorkspace: Workspace?,
        previousWorkspace: Workspace?,
        stageViewportFrame: CGRect?
    ) async
}

enum ChoreographyOutcome: Equatable, Sendable {
    case applied
    case blocked(ChoreographyBlockReason)
}

enum ChoreographyBlockReason: Equatable, Sendable {
    case accessibilityDenied
}

enum ChoreographyFocusPolicy: Equatable, Sendable {
    case focusActiveSlot
    case preserveExternalFocus
}

@MainActor
final class WindowChoreographyService: WindowChoreographing {
    private let windowRegistry: any WindowRegistryService & WindowControlling
    private let visibilityCoordinator: VisibilityCoordinator
    private let adapterRegistry: AdapterRegistry
    private let windowSlotMatcher = WindowSlotMatcher()

    private let logger = Logger(subsystem: "dev.nexusniri.Nexus", category: "choreography")

    init(
        windowRegistry: any WindowRegistryService & WindowControlling,
        visibilityCoordinator: VisibilityCoordinator,
        adapterRegistry: AdapterRegistry
    ) {
        self.windowRegistry = windowRegistry
        self.visibilityCoordinator = visibilityCoordinator
        self.adapterRegistry = adapterRegistry
    }

    func apply(
        workspace: Workspace,
        previousWorkspace: Workspace?,
        layout: LayoutPlan,
        stageViewportFrame: CGRect?,
        focusPolicy: ChoreographyFocusPolicy
    ) async -> ChoreographyOutcome {
        do {
            let snapshot = try await windowRegistry.snapshot()
            let actions = try await visibilityCoordinator.transition(
                from: previousWorkspace,
                to: workspace,
                layout: layout,
                windows: snapshot.windows
            )
            let (permittedActions, blockedReason) = filterActionsForPermissions(
                actions,
                currentWorkspace: workspace,
                previousWorkspace: previousWorkspace,
                isAccessibilityTrusted: snapshot.isAccessibilityTrusted
            )
            await apply(
                actions: permittedActions,
                layout: layout,
                stageViewportFrame: stageViewportFrame,
                currentWorkspace: workspace,
                previousWorkspace: previousWorkspace,
                windows: snapshot.windows,
                focusPolicy: focusPolicy
            )
            return blockedReason.map(ChoreographyOutcome.blocked) ?? .applied
        } catch {
            logger.error("Failed to apply window choreography for workspace \(workspace.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .applied
        }
    }

    func revealAll(currentWorkspace: Workspace?, previousWorkspace: Workspace?, stageViewportFrame: CGRect?) async {
        do {
            try await visibilityCoordinator.panicRevealAll()
            let snapshot = try await windowRegistry.snapshot()
            let actions = await visibilityCoordinator.currentActions()
            await apply(
                actions: actions,
                layout: nil,
                stageViewportFrame: stageViewportFrame,
                currentWorkspace: currentWorkspace,
                previousWorkspace: previousWorkspace,
                windows: snapshot.windows,
                focusPolicy: .preserveExternalFocus
            )
        } catch {
            logger.error("Failed to reveal all windows: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func apply(
        actions: [VisibilityAction],
        layout: LayoutPlan?,
        stageViewportFrame: CGRect?,
        currentWorkspace: Workspace?,
        previousWorkspace: Workspace?,
        windows: [WindowCandidate],
        focusPolicy: ChoreographyFocusPolicy
    ) async {
        var focusTarget: FocusTarget?
        var visibleNativeCandidates: [WindowCandidate] = []
        let preservedExternalFocusTarget: FocusTarget?

        if focusPolicy == .preserveExternalFocus,
           let candidate = (try? await windowRegistry.focusedWindowCandidate()) ?? nil,
           candidate.processID != Int(ProcessInfo.processInfo.processIdentifier) {
            preservedExternalFocusTarget = .native(candidate)
        } else {
            preservedExternalFocusTarget = nil
        }

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
            let stageResult = await apply(
                action: action,
                slot: slot,
                candidate: candidate,
                activeSlotID: currentWorkspace?.activeSlotID,
                layout: layout,
                stageViewportFrame: stageViewportFrame
            )

            if action.kind == .show || action.kind == .reveal,
               let visibleCandidate = stageResult.visibleNativeCandidate {
                visibleNativeCandidates.append(visibleCandidate)
            }

            if action.kind == .show || action.kind == .reveal,
               slot.id == currentWorkspace?.activeSlotID {
                focusTarget = stageResult.focusTarget
            }
        }

        let finalFocusTarget: FocusTarget? = switch focusPolicy {
        case .focusActiveSlot:
            focusTarget
        case .preserveExternalFocus:
            preservedExternalFocusTarget
        }

        await bringVisibleWindowsForward(
            visibleNativeCandidates,
            restoringFocusTo: finalFocusTarget
        )
    }

    private func filterActionsForPermissions(
        _ actions: [VisibilityAction],
        currentWorkspace: Workspace?,
        previousWorkspace: Workspace?,
        isAccessibilityTrusted: Bool
    ) -> ([VisibilityAction], ChoreographyBlockReason?) {
        guard isAccessibilityTrusted == false else {
            return (actions, nil)
        }

        var permittedActions: [VisibilityAction] = []
        var blockedReason: ChoreographyBlockReason?

        for action in actions {
            guard let slot = slot(
                withID: action.slotID,
                currentWorkspace: currentWorkspace,
                previousWorkspace: previousWorkspace
            ) else {
                permittedActions.append(action)
                continue
            }

            if requiresAccessibilityTrust(slot: slot, action: action) {
                blockedReason = .accessibilityDenied
                continue
            }

            permittedActions.append(action)
        }

        return (permittedActions, blockedReason)
    }

    private func requiresAccessibilityTrust(slot: Slot, action: VisibilityAction) -> Bool {
        guard slot.kind == .externalWindow else { return false }
        guard slot.adapterID == nil else { return false }

        switch action.kind {
        case .show, .reveal, .park, .minimize, .hideApp:
            return true
        case .detach:
            return false
        }
    }

    private func apply(
        action: VisibilityAction,
        slot: Slot,
        candidate: WindowCandidate?,
        activeSlotID: String?,
        layout: LayoutPlan?,
        stageViewportFrame: CGRect?
    ) async -> StageResult {
        if let adapter = adapter(for: slot) {
            let didHandle = await applyAdapterAction(
                adapter,
                action: action,
                slot: slot,
                shouldFocus: false
            )
            if didHandle {
                switch action.kind {
                case .show, .reveal:
                    if slot.id == activeSlotID {
                        return StageResult(
                            focusTarget: .adapter(adapter, slot),
                            visibleNativeCandidate: candidate
                        )
                    }
                    return StageResult(visibleNativeCandidate: candidate)
                case .park:
                    await parkWindow(slot: slot, action: action, candidate: candidate)
                    return StageResult()
                case .minimize:
                    if let candidate {
                        do {
                            try await windowRegistry.setWindowMinimized(
                                processID: candidate.processID,
                                windowID: candidate.windowID,
                                to: true
                            )
                        } catch {
                            logger.debug("Unable to minimize adapter-managed window for slot \(slot.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        }
                    }
                    return StageResult()
                case .hideApp:
                    if let candidate {
                        do {
                            try await windowRegistry.setApplicationHidden(processID: candidate.processID, to: true)
                        } catch {
                            logger.debug("Unable to hide adapter-managed app for slot \(slot.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        }
                    }
                    return StageResult()
                case .detach:
                    return StageResult()
                }
            }
        }

        switch action.kind {
        case .show, .reveal:
            let resolvedCandidate = await stageVisibleWindow(
                slot: slot,
                action: action,
                candidate: candidate,
                layout: layout,
                stageViewportFrame: stageViewportFrame
            )
            if slot.id == activeSlotID, let resolvedCandidate {
                return StageResult(
                    focusTarget: .native(resolvedCandidate),
                    visibleNativeCandidate: resolvedCandidate
                )
            }
            if let resolvedCandidate {
                return StageResult(visibleNativeCandidate: resolvedCandidate)
            }
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

        return StageResult()
    }

    private func stageVisibleWindow(
        slot: Slot,
        action: VisibilityAction,
        candidate: WindowCandidate?,
        layout: LayoutPlan?,
        stageViewportFrame: CGRect?
    ) async -> WindowCandidate? {
        guard let candidate else {
            do {
                try openTarget(for: slot)
            } catch {
                logger.debug("Unable to open target for slot \(slot.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return nil
            }

            if let reacquiredCandidate = await waitForCandidate(for: slot, action: action) {
                await applyResolvedWindowFrame(
                    slot: slot,
                    action: action,
                    candidate: reacquiredCandidate,
                    layout: layout,
                    stageViewportFrame: stageViewportFrame
                )
                return reacquiredCandidate
            } else {
                logger.debug("No live window candidate appeared after activating slot \(slot.id, privacy: .public).")
            }
            return nil
        }

        await applyResolvedWindowFrame(
            slot: slot,
            action: action,
            candidate: candidate,
            layout: layout,
            stageViewportFrame: stageViewportFrame
        )
        return candidate
    }

    private func applyResolvedWindowFrame(
        slot: Slot,
        action: VisibilityAction,
        candidate: WindowCandidate,
        layout: LayoutPlan?,
        stageViewportFrame: CGRect?
    ) async {
        do {
            try await windowRegistry.setApplicationHidden(processID: candidate.processID, to: false)
        } catch {
            logger.debug("Unable to unhide app for slot \(slot.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }

        do {
            try await windowRegistry.setWindowMinimized(
                processID: candidate.processID,
                windowID: candidate.windowID,
                to: false
            )
        } catch {
            logger.debug("Unable to restore minimized window for slot \(slot.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }

        if let targetFrame = resolvedStageFrame(
            for: slot,
            action: action,
            layout: layout,
            stageViewportFrame: stageViewportFrame
        ) {
            do {
                try await windowRegistry.setWindowFrame(
                    processID: candidate.processID,
                    windowID: candidate.windowID,
                    to: targetFrame
                )
            } catch {
                logger.debug("Unable to set frame for slot \(slot.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        do {
            try await windowRegistry.raiseWindow(
                processID: candidate.processID,
                windowID: candidate.windowID
            )
        } catch {
            logger.debug("Unable to raise visible window for slot \(slot.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func parkWindow(
        slot: Slot,
        action: VisibilityAction,
        candidate: WindowCandidate?
    ) async {
        if let candidate, let targetFrame = action.targetFrame, !shouldMinimizeWhenParking(slot: slot, targetFrame: targetFrame) {
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

            do {
                try await windowRegistry.setApplicationHidden(processID: candidate.processID, to: true)
                return
            } catch {
                logger.debug("Unable to hide parked app for slot \(slot.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
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
        windowSlotMatcher.bestCandidate(
            for: slot,
            preferredWindowID: action.windowID,
            in: windows
        )
    }

    private func shouldMinimizeWhenParking(slot: Slot, targetFrame: RectValue) -> Bool {
        _ = slot
        return targetFrame.width <= 24 || targetFrame.height <= 280
    }

    private func resolvedStageFrame(
        for slot: Slot,
        action: VisibilityAction,
        layout: LayoutPlan?,
        stageViewportFrame: CGRect?
    ) -> RectValue? {
        guard action.kind == .show || action.kind == .reveal,
              let layout,
              let slotLayout = layout.slotLayouts.first(where: { $0.slotID == slot.id }),
              let stageViewportFrame else {
            return action.targetFrame
        }

        let x = stageViewportFrame.minX + (slotLayout.frame.x - layout.scrollOffset)
        let topEdgeInScreenSpace = stageViewportFrame.maxY - ChromeMetrics.slotHeaderHeight - slotLayout.frame.y
        let y = accessibilityScreenY(
            forTopEdgeInScreenSpace: topEdgeInScreenSpace,
            stageViewportFrame: stageViewportFrame
        )

        return RectValue(
            x: x,
            y: y,
            width: slotLayout.frame.width,
            height: slotLayout.frame.height
        )
    }

    private func accessibilityScreenY(
        forTopEdgeInScreenSpace topEdgeInScreenSpace: Double,
        stageViewportFrame: CGRect
    ) -> Double {
        let matchingScreen = NSScreen.screens
            .max { lhs, rhs in
                lhs.frame.intersection(stageViewportFrame).area < rhs.frame.intersection(stageViewportFrame).area
            }
            ?? NSScreen.main

        guard let screenFrame = matchingScreen?.frame else {
            return topEdgeInScreenSpace
        }

        return screenFrame.maxY - topEdgeInScreenSpace
    }

    private func waitForCandidate(
        for slot: Slot,
        action: VisibilityAction,
        attempts: Int = 4,
        delayNanoseconds: UInt64 = 150_000_000
    ) async -> WindowCandidate? {
        guard attempts > 0 else { return nil }

        for attempt in 0..<attempts {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }

            guard let snapshot = try? await windowRegistry.snapshot() else {
                continue
            }

            if let candidate = resolveCandidate(for: slot, action: action, windows: snapshot.windows) {
                return candidate
            }
        }

        return nil
    }

    private func adapter(for slot: Slot) -> (any NexusAdapter)? {
        guard slot.adapterID != nil else { return nil }
        return adapterRegistry.adapter(for: slot)
    }

    private func applyAdapterAction(
        _ adapter: any NexusAdapter,
        action: VisibilityAction,
        slot: Slot,
        shouldFocus: Bool
    ) async -> Bool {
        do {
            switch action.kind {
            case .show, .reveal:
                try await adapter.stage(slot: slot, action: action)
                if shouldFocus {
                    try await adapter.activate(slot: slot)
                }
                return true
            case .park, .minimize, .hideApp:
                try await adapter.park(slot: slot)
                return true
            case .detach:
                return false
            }
        } catch {
            logger.debug("Adapter \(adapter.id, privacy: .public) failed for slot \(slot.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
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

    private func focus(_ target: FocusTarget) async {
        switch target {
        case .native(let candidate):
            do {
                try await windowRegistry.focusWindow(processID: candidate.processID, windowID: candidate.windowID)
            } catch {
                logger.debug("Unable to focus window for slot candidate \(candidate.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        case .adapter(let adapter, let slot):
            do {
                try await adapter.activate(slot: slot)
            } catch {
                logger.debug("Unable to activate adapter-managed slot \(slot.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func bringVisibleWindowsForward(
        _ candidates: [WindowCandidate],
        restoringFocusTo focusTarget: FocusTarget?
    ) async {
        var seenWindowKeys: Set<String> = []
        let orderedCandidates = candidates.filter { candidate in
            let key = "\(candidate.processID):\(candidate.windowID ?? -1)"
            return seenWindowKeys.insert(key).inserted
        }

        for candidate in orderedCandidates {
            do {
                try await windowRegistry.activateApplication(processID: candidate.processID)
            } catch {
                logger.debug("Unable to activate visible app for process \(candidate.processID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }

            do {
                try await windowRegistry.raiseWindow(processID: candidate.processID, windowID: candidate.windowID)
            } catch {
                logger.debug("Unable to bring visible window forward for candidate \(candidate.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        if let focusTarget {
            await focus(focusTarget)
        }
    }
}

private extension CGRect {
    var area: CGFloat {
        guard isNull == false, isEmpty == false else { return 0 }
        return width * height
    }
}

private struct StageResult {
    var focusTarget: FocusTarget?
    var visibleNativeCandidate: WindowCandidate?
}

private enum FocusTarget {
    case native(WindowCandidate)
    case adapter(any NexusAdapter, Slot)
}
