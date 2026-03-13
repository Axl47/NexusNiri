import Foundation

struct FocusedWindowAttribution {
    enum Decision: Equatable {
        case useFocusedOwner
        case useFrontmostHost
        case ignoreFrontmostNexus
        case ignoreMissingHostWindow
        case unresolved
    }

    struct Context: Equatable {
        let focusedElementProcessID: Int?
        let focusedWindowProcessID: Int?
        let focusedApplicationProcessID: Int?
        let focusedApplicationBundleID: String?
        let focusedWindowRole: String?
        let focusedWindowSubrole: String?
        let frontmostApplicationProcessID: Int?
        let frontmostApplicationBundleID: String?
        let hostStandardWindowAvailable: Bool
    }

    struct Resolution: Equatable {
        let decision: Decision
        let helperToHostAttributionUsed: Bool
        let focusedElementProcessID: Int?
        let focusedWindowProcessID: Int?
        let focusedApplicationProcessID: Int?
        let focusedApplicationBundleID: String?
        let focusedWindowRole: String?
        let focusedWindowSubrole: String?
        let frontmostApplicationProcessID: Int?
        let frontmostApplicationBundleID: String?
        let resolvedOwnerProcessID: Int?
        let resolvedOwnerBundleID: String?
    }

    func resolve(
        _ context: Context,
        nexusProcessID: Int,
        nexusBundleID: String?
    ) -> Resolution {
        let focusedOwnerProcessID = context.focusedWindowProcessID
            ?? context.focusedElementProcessID
            ?? context.focusedApplicationProcessID

        if matchesNexus(
            processID: context.frontmostApplicationProcessID,
            bundleID: context.frontmostApplicationBundleID,
            nexusProcessID: nexusProcessID,
            nexusBundleID: nexusBundleID
        ) {
            return Resolution(
                decision: .ignoreFrontmostNexus,
                helperToHostAttributionUsed: false,
                focusedElementProcessID: context.focusedElementProcessID,
                focusedWindowProcessID: context.focusedWindowProcessID,
                focusedApplicationProcessID: context.focusedApplicationProcessID,
                focusedApplicationBundleID: context.focusedApplicationBundleID,
                focusedWindowRole: context.focusedWindowRole,
                focusedWindowSubrole: context.focusedWindowSubrole,
                frontmostApplicationProcessID: context.frontmostApplicationProcessID,
                frontmostApplicationBundleID: context.frontmostApplicationBundleID,
                resolvedOwnerProcessID: nil,
                resolvedOwnerBundleID: nil
            )
        }

        if let frontmostProcessID = context.frontmostApplicationProcessID {
            if focusedOwnerProcessID == frontmostProcessID || focusedOwnerProcessID == nil {
                return Resolution(
                    decision: .useFocusedOwner,
                    helperToHostAttributionUsed: false,
                    focusedElementProcessID: context.focusedElementProcessID,
                    focusedWindowProcessID: context.focusedWindowProcessID,
                    focusedApplicationProcessID: context.focusedApplicationProcessID,
                    focusedApplicationBundleID: context.focusedApplicationBundleID,
                    focusedWindowRole: context.focusedWindowRole,
                    focusedWindowSubrole: context.focusedWindowSubrole,
                    frontmostApplicationProcessID: context.frontmostApplicationProcessID,
                    frontmostApplicationBundleID: context.frontmostApplicationBundleID,
                    resolvedOwnerProcessID: frontmostProcessID,
                    resolvedOwnerBundleID: context.frontmostApplicationBundleID ?? context.focusedApplicationBundleID
                )
            }

            if context.hostStandardWindowAvailable {
                return Resolution(
                    decision: .useFrontmostHost,
                    helperToHostAttributionUsed: true,
                    focusedElementProcessID: context.focusedElementProcessID,
                    focusedWindowProcessID: context.focusedWindowProcessID,
                    focusedApplicationProcessID: context.focusedApplicationProcessID,
                    focusedApplicationBundleID: context.focusedApplicationBundleID,
                    focusedWindowRole: context.focusedWindowRole,
                    focusedWindowSubrole: context.focusedWindowSubrole,
                    frontmostApplicationProcessID: context.frontmostApplicationProcessID,
                    frontmostApplicationBundleID: context.frontmostApplicationBundleID,
                    resolvedOwnerProcessID: frontmostProcessID,
                    resolvedOwnerBundleID: context.frontmostApplicationBundleID
                )
            }

            return Resolution(
                decision: .ignoreMissingHostWindow,
                helperToHostAttributionUsed: false,
                focusedElementProcessID: context.focusedElementProcessID,
                focusedWindowProcessID: context.focusedWindowProcessID,
                focusedApplicationProcessID: context.focusedApplicationProcessID,
                focusedApplicationBundleID: context.focusedApplicationBundleID,
                focusedWindowRole: context.focusedWindowRole,
                focusedWindowSubrole: context.focusedWindowSubrole,
                frontmostApplicationProcessID: context.frontmostApplicationProcessID,
                frontmostApplicationBundleID: context.frontmostApplicationBundleID,
                resolvedOwnerProcessID: nil,
                resolvedOwnerBundleID: nil
            )
        }

        if matchesNexus(
            processID: focusedOwnerProcessID,
            bundleID: context.focusedApplicationBundleID,
            nexusProcessID: nexusProcessID,
            nexusBundleID: nexusBundleID
        ) {
            return Resolution(
                decision: .ignoreFrontmostNexus,
                helperToHostAttributionUsed: false,
                focusedElementProcessID: context.focusedElementProcessID,
                focusedWindowProcessID: context.focusedWindowProcessID,
                focusedApplicationProcessID: context.focusedApplicationProcessID,
                focusedApplicationBundleID: context.focusedApplicationBundleID,
                focusedWindowRole: context.focusedWindowRole,
                focusedWindowSubrole: context.focusedWindowSubrole,
                frontmostApplicationProcessID: context.frontmostApplicationProcessID,
                frontmostApplicationBundleID: context.frontmostApplicationBundleID,
                resolvedOwnerProcessID: nil,
                resolvedOwnerBundleID: nil
            )
        }

        guard let focusedOwnerProcessID else {
            return Resolution(
                decision: .unresolved,
                helperToHostAttributionUsed: false,
                focusedElementProcessID: context.focusedElementProcessID,
                focusedWindowProcessID: context.focusedWindowProcessID,
                focusedApplicationProcessID: context.focusedApplicationProcessID,
                focusedApplicationBundleID: context.focusedApplicationBundleID,
                focusedWindowRole: context.focusedWindowRole,
                focusedWindowSubrole: context.focusedWindowSubrole,
                frontmostApplicationProcessID: context.frontmostApplicationProcessID,
                frontmostApplicationBundleID: context.frontmostApplicationBundleID,
                resolvedOwnerProcessID: nil,
                resolvedOwnerBundleID: nil
            )
        }

        return Resolution(
            decision: .useFocusedOwner,
            helperToHostAttributionUsed: false,
            focusedElementProcessID: context.focusedElementProcessID,
            focusedWindowProcessID: context.focusedWindowProcessID,
            focusedApplicationProcessID: context.focusedApplicationProcessID,
            focusedApplicationBundleID: context.focusedApplicationBundleID,
            focusedWindowRole: context.focusedWindowRole,
            focusedWindowSubrole: context.focusedWindowSubrole,
            frontmostApplicationProcessID: context.frontmostApplicationProcessID,
            frontmostApplicationBundleID: context.frontmostApplicationBundleID,
            resolvedOwnerProcessID: focusedOwnerProcessID,
            resolvedOwnerBundleID: context.focusedApplicationBundleID
        )
    }

    private func matchesNexus(
        processID: Int?,
        bundleID: String?,
        nexusProcessID: Int,
        nexusBundleID: String?
    ) -> Bool {
        if processID == nexusProcessID {
            return true
        }

        guard let bundleID, let nexusBundleID else {
            return false
        }

        return bundleID.caseInsensitiveCompare(nexusBundleID) == .orderedSame
    }
}
