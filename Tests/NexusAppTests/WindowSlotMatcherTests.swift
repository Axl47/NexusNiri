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
