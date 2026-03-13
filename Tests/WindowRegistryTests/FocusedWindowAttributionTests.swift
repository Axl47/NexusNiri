import Testing
@testable import WindowRegistry

@Test
func focusedWindowAttributionKeepsMainAppOwnershipWhenFocusedProcessMatchesFrontmostApp() {
    let attribution = FocusedWindowAttribution()

    let resolution = attribution.resolve(
        .init(
            focusedElementProcessID: 101,
            focusedWindowProcessID: 101,
            focusedApplicationProcessID: 101,
            focusedApplicationBundleID: "dev.zed.Zed",
            focusedWindowRole: "AXWindow",
            focusedWindowSubrole: "AXStandardWindow",
            frontmostApplicationProcessID: 101,
            frontmostApplicationBundleID: "dev.zed.Zed",
            hostStandardWindowAvailable: true
        ),
        nexusProcessID: 999,
        nexusBundleID: "dev.nexusniri.Nexus"
    )

    #expect(resolution.decision == .useFocusedOwner)
    #expect(resolution.helperToHostAttributionUsed == false)
    #expect(resolution.resolvedOwnerProcessID == 101)
    #expect(resolution.resolvedOwnerBundleID == "dev.zed.Zed")
}

@Test
func focusedWindowAttributionRemapsZenHelperContentToFrontmostHostApp() {
    let attribution = FocusedWindowAttribution()

    let resolution = attribution.resolve(
        .init(
            focusedElementProcessID: 3237,
            focusedWindowProcessID: 3237,
            focusedApplicationProcessID: 3237,
            focusedApplicationBundleID: "app.zen-browser.plugincontainer",
            focusedWindowRole: "AXWindow",
            focusedWindowSubrole: "AXStandardWindow",
            frontmostApplicationProcessID: 687,
            frontmostApplicationBundleID: "app.zen-browser.zen",
            hostStandardWindowAvailable: true
        ),
        nexusProcessID: 999,
        nexusBundleID: "dev.nexusniri.Nexus"
    )

    #expect(resolution.decision == .useFrontmostHost)
    #expect(resolution.helperToHostAttributionUsed)
    #expect(resolution.resolvedOwnerProcessID == 687)
    #expect(resolution.resolvedOwnerBundleID == "app.zen-browser.zen")
}

@Test
func focusedWindowAttributionRemapsTetherHostedContentToFrontmostHostApp() {
    let attribution = FocusedWindowAttribution()

    let resolution = attribution.resolve(
        .init(
            focusedElementProcessID: 8245,
            focusedWindowProcessID: 8245,
            focusedApplicationProcessID: 8245,
            focusedApplicationBundleID: "com.apple.SafariPlatformSupport.Helper",
            focusedWindowRole: "AXWindow",
            focusedWindowSubrole: "AXStandardWindow",
            frontmostApplicationProcessID: 7131,
            frontmostApplicationBundleID: "com.t3tools.tether",
            hostStandardWindowAvailable: true
        ),
        nexusProcessID: 999,
        nexusBundleID: "dev.nexusniri.Nexus"
    )

    #expect(resolution.decision == .useFrontmostHost)
    #expect(resolution.helperToHostAttributionUsed)
    #expect(resolution.resolvedOwnerProcessID == 7131)
    #expect(resolution.resolvedOwnerBundleID == "com.t3tools.tether")
}

@Test
func focusedWindowAttributionIgnoresHelperOwnedSurfaceWhenNoHostStandardWindowIsAvailable() {
    let attribution = FocusedWindowAttribution()

    let resolution = attribution.resolve(
        .init(
            focusedElementProcessID: 8245,
            focusedWindowProcessID: 8245,
            focusedApplicationProcessID: 8245,
            focusedApplicationBundleID: "com.apple.SafariPlatformSupport.Helper",
            focusedWindowRole: "AXSheet",
            focusedWindowSubrole: nil,
            frontmostApplicationProcessID: 7131,
            frontmostApplicationBundleID: "com.t3tools.tether",
            hostStandardWindowAvailable: false
        ),
        nexusProcessID: 999,
        nexusBundleID: "dev.nexusniri.Nexus"
    )

    #expect(resolution.decision == .ignoreMissingHostWindow)
    #expect(resolution.resolvedOwnerProcessID == nil)
}

@Test
func focusedWindowAttributionIgnoresNexusWhenItIsFrontmost() {
    let attribution = FocusedWindowAttribution()

    let resolution = attribution.resolve(
        .init(
            focusedElementProcessID: 1000,
            focusedWindowProcessID: 1000,
            focusedApplicationProcessID: 1000,
            focusedApplicationBundleID: "dev.nexusniri.Nexus",
            focusedWindowRole: "AXWindow",
            focusedWindowSubrole: "AXStandardWindow",
            frontmostApplicationProcessID: 1000,
            frontmostApplicationBundleID: "dev.nexusniri.Nexus",
            hostStandardWindowAvailable: true
        ),
        nexusProcessID: 1000,
        nexusBundleID: "dev.nexusniri.Nexus"
    )

    #expect(resolution.decision == .ignoreFrontmostNexus)
    #expect(resolution.resolvedOwnerProcessID == nil)
}
