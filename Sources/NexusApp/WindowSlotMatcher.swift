import Foundation
import SharedTypes

struct WindowSlotMatcher {
    struct CandidateMatch: Equatable {
        let candidate: WindowCandidate
        let confidence: Double
    }

    struct SlotMatch: Equatable {
        let workspaceID: String
        let slotID: String
        let confidence: Double
    }

    func bestCandidate(
        for slot: Slot,
        preferredWindowID: Int?,
        in windows: [WindowCandidate]
    ) -> WindowCandidate? {
        bestCandidateMatch(
            for: slot,
            preferredWindowID: preferredWindowID,
            in: windows
        )?.candidate
    }

    func bestCandidateMatch(
        for slot: Slot,
        preferredWindowID: Int?,
        in windows: [WindowCandidate]
    ) -> CandidateMatch? {
        windows
            .compactMap { candidate -> (candidate: WindowCandidate, score: Int)? in
                guard let score = forwardScore(slot: slot, candidate: candidate, preferredWindowID: preferredWindowID) else {
                    return nil
                }
                return (candidate, score)
            }
            .max { lhs, rhs in lhs.score < rhs.score }
            .map { best in
                CandidateMatch(
                    candidate: best.candidate,
                    confidence: matchConfidence(
                        for: best.score,
                        exactWindowBindingMatch: slot.runtimeBinding?.windowID == best.candidate.windowID
                    )
                )
            }
    }

    func bestSlotMatch(
        for candidate: WindowCandidate,
        in workspaces: [Workspace],
        preferredWorkspaceID: String? = nil,
        ignoringBundleID: String?,
        ignoringProcessID: Int
    ) -> SlotMatch? {
        guard candidate.processID != ignoringProcessID else { return nil }
        if let ignoringBundleID, canonicalBundleID(candidate.bundleID) == canonicalBundleID(ignoringBundleID) {
            return nil
        }

        let scoredMatches = workspaces.flatMap { workspace in
            workspace.orderedSlots.compactMap { slot -> ReverseSlotScore? in
                guard let scored = reverseScore(slot: slot, candidate: candidate) else {
                    return nil
                }

                return ReverseSlotScore(
                    workspaceID: workspace.id,
                    slotID: slot.id,
                    score: scored.score,
                    exact: scored.exactWindowBindingMatch,
                    bundleOnlyHeuristic: scored.bundleOnlyHeuristic
                )
            }
        }

        guard let best = scoredMatches.max(by: { lhs, rhs in lhs.score < rhs.score }) else {
            return nil
        }

        if best.exact == false {
            if best.score < 160 {
                let bundleOnlyUniqueMatch = best.bundleOnlyHeuristic && scoredMatches.count == 1
                guard bundleOnlyUniqueMatch else { return nil }
            }

            let collisions = scoredMatches.filter {
                $0.score == best.score &&
                !($0.workspaceID == best.workspaceID && $0.slotID == best.slotID)
            }
            if collisions.isEmpty == false {
                if let preferredWorkspaceID {
                    let preferredMatches = scoredMatches.filter {
                        $0.score == best.score && $0.workspaceID == preferredWorkspaceID
                    }

                    guard preferredMatches.count == 1,
                          let preferredMatch = preferredMatches.first else {
                        return nil
                    }

                    return SlotMatch(
                        workspaceID: preferredMatch.workspaceID,
                        slotID: preferredMatch.slotID,
                        confidence: matchConfidence(
                            for: preferredMatch.score,
                            exactWindowBindingMatch: preferredMatch.exact
                        )
                    )
                }

                return nil
            }
        }

        return SlotMatch(
            workspaceID: best.workspaceID,
            slotID: best.slotID,
            confidence: matchConfidence(for: best.score, exactWindowBindingMatch: best.exact)
        )
    }

    private func forwardScore(
        slot: Slot,
        candidate: WindowCandidate,
        preferredWindowID: Int?
    ) -> Int? {
        let exactPreferredWindow = preferredWindowID != nil && preferredWindowID == candidate.windowID
        let exactRuntimeWindow = slot.runtimeBinding?.windowID != nil && slot.runtimeBinding?.windowID == candidate.windowID
        let runtimeProcessMatch = slot.runtimeBinding?.processID == candidate.processID
        let bundleMatch = bundleMatches(slot: slot, candidate: candidate)
        let titleMatch = titleMatches(slot: slot, candidate: candidate)
        let bundleMatchAllowed = bundleMatch && (slot.targetingMode == .application || titleMatch)

        guard exactPreferredWindow || exactRuntimeWindow || runtimeProcessMatch || bundleMatchAllowed else {
            return nil
        }

        var score = 0
        if exactPreferredWindow { score += 1_000 }
        if exactRuntimeWindow { score += 900 }
        if runtimeProcessMatch { score += 250 }
        if bundleMatchAllowed { score += 120 }
        if titleMatch { score += 80 }
        if candidate.source == .accessibility { score += 30 }
        if candidate.isFocused { score += 20 }
        if slot.runtimeBinding?.state == .attached { score += 10 }
        if candidate.isMinimized { score -= 50 }

        return score
    }

    private func reverseScore(
        slot: Slot,
        candidate: WindowCandidate
    ) -> (score: Int, exactWindowBindingMatch: Bool, bundleOnlyHeuristic: Bool)? {
        let exactWindowBindingMatch = slot.runtimeBinding?.windowID != nil && slot.runtimeBinding?.windowID == candidate.windowID
        let runtimeProcessMatch = slot.runtimeBinding?.processID == candidate.processID
        let bundleMatch = bundleMatches(slot: slot, candidate: candidate)
        let titleMatch = titleMatches(slot: slot, candidate: candidate)
        let bundleMatchAllowed = bundleMatch && (slot.targetingMode == .application || titleMatch)

        guard exactWindowBindingMatch || runtimeProcessMatch || bundleMatchAllowed else {
            return nil
        }

        var score = 0
        if exactWindowBindingMatch { score += 1_000 }
        if runtimeProcessMatch { score += 260 }
        if bundleMatchAllowed { score += 120 }
        if titleMatch { score += 80 }
        if candidate.source == .accessibility { score += 30 }
        if slot.runtimeBinding?.state == .attached { score += 15 }
        if candidate.isFocused { score += 10 }

        if exactWindowBindingMatch == false, runtimeProcessMatch == false, titleMatch == false {
            score -= 40
        }

        return (
            score,
            exactWindowBindingMatch,
            slot.targetingMode == .application &&
                bundleMatchAllowed &&
                exactWindowBindingMatch == false &&
                runtimeProcessMatch == false &&
                titleMatch == false
        )
    }

    private func bundleMatches(slot: Slot, candidate: WindowCandidate) -> Bool {
        guard let slotBundleID = canonicalBundleID(slot.appBinding?.bundleID) else {
            return false
        }
        return slotBundleID == canonicalBundleID(candidate.bundleID)
    }

    private func titleMatches(slot: Slot, candidate: WindowCandidate) -> Bool {
        let titleHints = slot.appBinding?.titleHints ?? []
        return titleHints.contains(where: { candidate.windowTitle.localizedCaseInsensitiveContains($0) })
    }

    private func matchConfidence(for score: Int, exactWindowBindingMatch: Bool) -> Double {
        if exactWindowBindingMatch {
            return 1.0
        }

        return min(Double(score) / 300.0, 0.95)
    }

    private func canonicalBundleID(_ bundleID: String?) -> String? {
        guard var bundleID = bundleID?.lowercased() else {
            return nil
        }

        if let helperRange = bundleID.range(of: ".helper"),
           helperRange.lowerBound != bundleID.startIndex {
            let suffix = bundleID[helperRange.lowerBound...]
            if suffix == ".helper" || suffix.hasPrefix(".helper.") {
                bundleID = String(bundleID[..<helperRange.lowerBound])
            }
        }

        switch bundleID {
        case "dev.tether.desktop",
             "com.t3tools.tether.dev",
             "com.t3tools.tether-dev":
            return "com.t3tools.tether"
        case let bundleID where bundleID.hasPrefix("dev.tether.desktop."):
            return "com.t3tools.tether"
        default:
            return bundleID
        }
    }
}

private struct ReverseSlotScore {
    let workspaceID: String
    let slotID: String
    let score: Int
    let exact: Bool
    let bundleOnlyHeuristic: Bool
}
