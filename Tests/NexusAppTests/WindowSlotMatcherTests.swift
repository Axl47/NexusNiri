import Foundation
import SharedTypes
import Testing
@testable import NexusApp

@Test
func windowSlotMatcherPrefersExactRuntimeBindingOverBundleOnlyMatches() {
    let matcher = WindowSlotMatcher()
    let exactSlot = Slot(
        id: "exact",
        workspaceID: "workspace",
        kind: .externalWindow,
        label: "Exact",
        appBinding: AppBinding(bundleID: "com.example.editor"),
        widthPolicy: SizePolicy(mode: .fraction, value: 0.5),
        layoutRole: .primary,
        runtimeBinding: RuntimeBinding(processID: 101, windowID: 7, matchConfidence: 1, state: .attached)
    )
    let bundleOnlySlot = Slot(
        id: "bundleOnly",
        workspaceID: "workspace",
        kind: .externalWindow,
        label: "Bundle Only",
        appBinding: AppBinding(bundleID: "com.example.editor"),
        widthPolicy: SizePolicy(mode: .fraction, value: 0.5),
        layoutRole: .secondary
    )
    let workspace = Workspace(
        id: "workspace",
        name: "Main",
        activeSlotID: exactSlot.id,
        slotOrder: [exactSlot.id, bundleOnlySlot.id],
        slots: [exactSlot, bundleOnlySlot]
    )

    let match = matcher.bestSlotMatch(
        for: WindowCandidate(
            bundleID: "com.example.editor",
            appName: "Editor",
            windowTitle: "Project",
            processID: 101,
            windowID: 7,
            frame: .zero,
            isFocused: true,
            source: .accessibility
        ),
        in: [workspace],
        ignoringBundleID: nil,
        ignoringProcessID: 999
    )

    #expect(match?.slotID == "exact")
    #expect(match?.confidence == 1)
}

@Test
func windowSlotMatcherUsesBundleAndTitleHintsWhenNoRuntimeBindingExists() {
    let matcher = WindowSlotMatcher()
    let slot = Slot(
        id: "browser",
        workspaceID: "workspace",
        kind: .externalWindow,
        label: "Browser",
        appBinding: AppBinding(bundleID: "com.example.browser", titleHints: ["Docs"]),
        widthPolicy: SizePolicy(mode: .fraction, value: 1),
        layoutRole: .primary
    )
    let workspace = Workspace(id: "workspace", name: "Main", activeSlotID: slot.id, slotOrder: [slot.id], slots: [slot])

    let match = matcher.bestSlotMatch(
        for: WindowCandidate(
            bundleID: "com.example.browser",
            appName: "Browser",
            windowTitle: "Docs - Nexus",
            processID: 202,
            windowID: 9,
            frame: .zero,
            isFocused: true,
            source: .accessibility
        ),
        in: [workspace],
        ignoringBundleID: nil,
        ignoringProcessID: 999
    )

    #expect(match?.slotID == "browser")
    #expect((match?.confidence ?? 0) > 0.5)
}

@Test
func windowSlotMatcherAcceptsUniqueBundleOnlyMatches() {
    let matcher = WindowSlotMatcher()
    let slot = Slot(
        id: "browser",
        workspaceID: "workspace",
        kind: .externalWindow,
        label: "Browser",
        appBinding: AppBinding(bundleID: "com.example.browser"),
        widthPolicy: SizePolicy(mode: .fraction, value: 1),
        layoutRole: .primary
    )
    let workspace = Workspace(id: "workspace", name: "Main", activeSlotID: slot.id, slotOrder: [slot.id], slots: [slot])

    let match = matcher.bestSlotMatch(
        for: WindowCandidate(
            bundleID: "com.example.browser",
            appName: "Browser",
            windowTitle: "Random Page",
            processID: 202,
            windowID: 9,
            frame: .zero,
            isFocused: true,
            source: .accessibility
        ),
        in: [workspace],
        ignoringBundleID: nil,
        ignoringProcessID: 999
    )

    #expect(match?.slotID == "browser")
}

@Test
func windowSlotMatcherRejectsAmbiguousSameBundleMatchesWithoutStrongerHints() {
    let matcher = WindowSlotMatcher()
    let first = Slot(
        id: "first",
        workspaceID: "workspace",
        kind: .externalWindow,
        label: "First",
        appBinding: AppBinding(bundleID: "com.example.browser"),
        widthPolicy: SizePolicy(mode: .fraction, value: 0.5),
        layoutRole: .primary
    )
    let second = Slot(
        id: "second",
        workspaceID: "workspace",
        kind: .externalWindow,
        label: "Second",
        appBinding: AppBinding(bundleID: "com.example.browser"),
        widthPolicy: SizePolicy(mode: .fraction, value: 0.5),
        layoutRole: .secondary
    )
    let workspace = Workspace(
        id: "workspace",
        name: "Main",
        activeSlotID: first.id,
        slotOrder: [first.id, second.id],
        slots: [first, second]
    )

    let match = matcher.bestSlotMatch(
        for: WindowCandidate(
            bundleID: "com.example.browser",
            appName: "Browser",
            windowTitle: "Window",
            processID: 202,
            windowID: 9,
            frame: .zero,
            isFocused: true,
            source: .accessibility
        ),
        in: [workspace],
        ignoringBundleID: nil,
        ignoringProcessID: 999
    )

    #expect(match == nil)
}

@Test
func windowSlotMatcherRejectsBundleOnlyReverseMatchesForWindowTargetedSlots() {
    let matcher = WindowSlotMatcher()
    let slot = Slot(
        id: "captured-browser",
        workspaceID: "workspace",
        kind: .externalWindow,
        targetingMode: .window,
        label: "Docs",
        appBinding: AppBinding(bundleID: "com.example.browser"),
        widthPolicy: SizePolicy(mode: .fraction, value: 0.5),
        layoutRole: .primary
    )
    let workspace = Workspace(id: "workspace", name: "Main", activeSlotID: slot.id, slotOrder: [slot.id], slots: [slot])

    let match = matcher.bestSlotMatch(
        for: WindowCandidate(
            bundleID: "com.example.browser",
            appName: "Browser",
            windowTitle: "Random Window",
            processID: 303,
            windowID: 11,
            frame: .zero,
            isFocused: true,
            source: .accessibility
        ),
        in: [workspace],
        ignoringBundleID: nil,
        ignoringProcessID: 999
    )

    #expect(match == nil)
}

@Test
func windowSlotMatcherPrefersPreferredWorkspaceWhenDuplicateSharedProcessMatchesTie() {
    let matcher = WindowSlotMatcher()
    let apiSlot = Slot(
        id: "api-zen",
        workspaceID: "api",
        kind: .externalWindow,
        label: "Zen",
        appBinding: AppBinding(bundleID: "app.zen-browser.zen"),
        widthPolicy: SizePolicy(mode: .fraction, value: 0.5),
        layoutRole: .secondary,
        runtimeBinding: RuntimeBinding(processID: 687, matchConfidence: 1, state: .attached)
    )
    let uiSlot = Slot(
        id: "ui-zen",
        workspaceID: "ui",
        kind: .externalWindow,
        label: "Zen",
        appBinding: AppBinding(bundleID: "app.zen-browser.zen"),
        widthPolicy: SizePolicy(mode: .fraction, value: 0.5),
        layoutRole: .secondary,
        runtimeBinding: RuntimeBinding(processID: 687, matchConfidence: 1, state: .attached)
    )
    let workspaces = [
        Workspace(id: "api", name: "API", activeSlotID: apiSlot.id, slotOrder: [apiSlot.id], slots: [apiSlot]),
        Workspace(id: "ui", name: "UI", activeSlotID: uiSlot.id, slotOrder: [uiSlot.id], slots: [uiSlot]),
    ]

    let match = matcher.bestSlotMatch(
        for: WindowCandidate(
            bundleID: "app.zen-browser.zen",
            appName: "Zen",
            windowTitle: "Docs",
            processID: 687,
            windowID: nil,
            frame: .zero,
            isFocused: true,
            source: .accessibility
        ),
        in: workspaces,
        preferredWorkspaceID: "api",
        ignoringBundleID: nil,
        ignoringProcessID: 999
    )

    #expect(match?.workspaceID == "api")
    #expect(match?.slotID == "api-zen")
}

@Test
func windowSlotMatcherStillRejectsDuplicateSharedProcessMatchesWithoutPreferredWorkspace() {
    let matcher = WindowSlotMatcher()
    let apiSlot = Slot(
        id: "api-tether",
        workspaceID: "api",
        kind: .hybrid,
        label: "Tether",
        appBinding: AppBinding(bundleID: "com.t3tools.tether"),
        widthPolicy: SizePolicy(mode: .fraction, value: 0.5),
        layoutRole: .support,
        runtimeBinding: RuntimeBinding(processID: 7131, matchConfidence: 1, state: .attached)
    )
    let uiSlot = Slot(
        id: "ui-tether",
        workspaceID: "ui",
        kind: .hybrid,
        label: "Tether",
        appBinding: AppBinding(bundleID: "com.t3tools.tether"),
        widthPolicy: SizePolicy(mode: .fraction, value: 0.5),
        layoutRole: .support,
        runtimeBinding: RuntimeBinding(processID: 7131, matchConfidence: 1, state: .attached)
    )
    let workspaces = [
        Workspace(id: "api", name: "API", activeSlotID: apiSlot.id, slotOrder: [apiSlot.id], slots: [apiSlot]),
        Workspace(id: "ui", name: "UI", activeSlotID: uiSlot.id, slotOrder: [uiSlot.id], slots: [uiSlot]),
    ]

    let match = matcher.bestSlotMatch(
        for: WindowCandidate(
            bundleID: "com.t3tools.tether",
            appName: "Tether",
            windowTitle: "Tether",
            processID: 7131,
            windowID: nil,
            frame: .zero,
            isFocused: true,
            source: .accessibility
        ),
        in: workspaces,
        ignoringBundleID: nil,
        ignoringProcessID: 999
    )

    #expect(match == nil)
}

@Test
func windowSlotMatcherCanonicalizesLegacyTetherBundleIDs() {
    let matcher = WindowSlotMatcher()
    let slot = Slot(
        id: "tether",
        workspaceID: "workspace",
        kind: .hybrid,
        label: "Tether",
        appBinding: AppBinding(bundleID: "com.t3tools.tether", titleHints: ["Session"]),
        widthPolicy: SizePolicy(mode: .fraction, value: 1),
        layoutRole: .support
    )
    let workspace = Workspace(id: "workspace", name: "Main", activeSlotID: slot.id, slotOrder: [slot.id], slots: [slot])

    let match = matcher.bestSlotMatch(
        for: WindowCandidate(
            bundleID: "dev.tether.desktop",
            appName: "Tether",
            windowTitle: "Session",
            processID: 404,
            windowID: 12,
            frame: .zero,
            isFocused: true,
            source: .accessibility
        ),
        in: [workspace],
        ignoringBundleID: nil,
        ignoringProcessID: 999
    )

    #expect(match?.slotID == "tether")
}

@Test
func windowSlotMatcherCanonicalizesTetherDevBundleIDs() {
    let matcher = WindowSlotMatcher()
    let slot = Slot(
        id: "tether",
        workspaceID: "workspace",
        kind: .hybrid,
        label: "Tether",
        appBinding: AppBinding(bundleID: "com.t3tools.tether", titleHints: ["Tether"]),
        widthPolicy: SizePolicy(mode: .fraction, value: 1),
        layoutRole: .support
    )
    let workspace = Workspace(id: "workspace", name: "Main", activeSlotID: slot.id, slotOrder: [slot.id], slots: [slot])

    let match = matcher.bestSlotMatch(
        for: WindowCandidate(
            bundleID: "com.t3tools.tether.dev",
            appName: "Tether (Dev)",
            windowTitle: "Tether",
            processID: 404,
            windowID: 12,
            frame: .zero,
            isFocused: true,
            source: .accessibility
        ),
        in: [workspace],
        ignoringBundleID: nil,
        ignoringProcessID: 999
    )

    #expect(match?.slotID == "tether")
}

@Test
func windowSlotMatcherCanonicalizesElectronHelperBundleIDs() {
    let matcher = WindowSlotMatcher()
    let slot = Slot(
        id: "editor",
        workspaceID: "workspace",
        kind: .externalWindow,
        label: "Editor",
        appBinding: AppBinding(bundleID: "com.microsoft.VSCode"),
        widthPolicy: SizePolicy(mode: .fraction, value: 1),
        layoutRole: .primary
    )
    let workspace = Workspace(id: "workspace", name: "Main", activeSlotID: slot.id, slotOrder: [slot.id], slots: [slot])

    let match = matcher.bestSlotMatch(
        for: WindowCandidate(
            bundleID: "com.microsoft.VSCode.helper",
            appName: "Code Helper",
            windowTitle: "main.swift",
            processID: 808,
            windowID: 42,
            frame: .zero,
            isFocused: true,
            source: .accessibility
        ),
        in: [workspace],
        ignoringBundleID: nil,
        ignoringProcessID: 999
    )

    #expect(match?.slotID == "editor")
}

@Test
func windowSlotMatcherDoesNotCanonicalizeGenericSafariPlatformHelpers() {
    let matcher = WindowSlotMatcher()
    let slot = Slot(
        id: "tether",
        workspaceID: "workspace",
        kind: .hybrid,
        label: "Tether",
        appBinding: AppBinding(bundleID: "com.t3tools.tether"),
        widthPolicy: SizePolicy(mode: .fraction, value: 1),
        layoutRole: .support
    )
    let workspace = Workspace(id: "workspace", name: "Main", activeSlotID: slot.id, slotOrder: [slot.id], slots: [slot])

    let match = matcher.bestSlotMatch(
        for: WindowCandidate(
            bundleID: "com.apple.SafariPlatformSupport.Helper",
            appName: "AutoFill (Tether (Dev))",
            windowTitle: "Tether",
            processID: 8245,
            windowID: 77,
            frame: .zero,
            isFocused: true,
            source: .accessibility
        ),
        in: [workspace],
        ignoringBundleID: nil,
        ignoringProcessID: 999
    )

    #expect(match == nil)
}
