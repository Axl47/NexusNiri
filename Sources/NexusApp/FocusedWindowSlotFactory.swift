import Foundation
import SharedTypes

struct FocusedWindowSlotFactory {
    private let presets: SlotPresetCatalog

    init(presets: SlotPresetCatalog = SlotPresetCatalog()) {
        self.presets = presets
    }

    func makeSlot(
        from candidate: WindowCandidate,
        workspaceID: String,
        existingLabels: Set<String>,
        now: Date = .now
    ) -> Slot? {
        guard let bundleID = SlotPresetCatalog.canonicalBundleID(candidate.bundleID) else {
            return nil
        }

        let preset = presets.preset(for: bundleID)
        let baseLabel = preferredBaseLabel(for: candidate, preset: preset)
        let label = uniquedLabel(baseLabel, existingLabels: existingLabels)

        return Slot(
            workspaceID: workspaceID,
            kind: preset?.kind ?? .externalWindow,
            targetingMode: .window,
            label: label,
            appBinding: AppBinding(
                bundleID: bundleID,
                titleHints: normalizedTitleHints(for: candidate),
                adapterHints: preset?.adapterHints ?? [:]
            ),
            widthPolicy: preset?.widthPolicy ?? SizePolicy(mode: .fraction, value: 0.5, minimum: 400),
            layoutRole: preset?.layoutRole ?? .primary,
            adapterID: preset?.adapterID,
            runtimeBinding: RuntimeBinding(
                processID: candidate.processID,
                windowID: candidate.windowID,
                matchConfidence: 1,
                state: .attached,
                lastSeenAt: now
            ),
            warmPreference: preset?.warmPreference ?? .warm,
            createdAt: now,
            updatedAt: now
        )
    }

    private func preferredBaseLabel(
        for candidate: WindowCandidate,
        preset: SlotPresetCatalog.SlotPreset?
    ) -> String {
        let trimmedTitle = candidate.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty == false,
           trimmedTitle.caseInsensitiveCompare(candidate.appName) != .orderedSame {
            return trimmedTitle
        }

        return preset?.defaultLabel ?? candidate.appName
    }

    private func normalizedTitleHints(for candidate: WindowCandidate) -> [String] {
        let separators = CharacterSet(charactersIn: "-—|:")
        let rawSegments = candidate.windowTitle
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { segment in
                segment.count >= 3 &&
                segment.caseInsensitiveCompare(candidate.appName) != .orderedSame
            }

        if rawSegments.isEmpty == false {
            return Array(rawSegments.prefix(2))
        }

        let trimmedTitle = candidate.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTitle.isEmpty == false,
              trimmedTitle.caseInsensitiveCompare(candidate.appName) != .orderedSame else {
            return []
        }

        return [trimmedTitle]
    }

    private func uniquedLabel(_ baseLabel: String, existingLabels: Set<String>) -> String {
        guard existingLabels.contains(baseLabel) else {
            return baseLabel
        }

        var suffix = 2
        while existingLabels.contains("\(baseLabel) \(suffix)") {
            suffix += 1
        }

        return "\(baseLabel) \(suffix)"
    }
}
