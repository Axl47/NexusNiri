import Foundation
import SharedTypes
import Testing
@testable import Diagnostics

@Test
func accessibilityDetailWarnsWhenDeniedOnAdHocBuild() {
    let detail = PermissionInspector.accessibilityDetail(
        trusted: false,
        buildIdentity: BuildIdentityStatus(
            bundlePath: "/tmp/Nexus.app",
            bundleIdentifier: "dev.nexusniri.Nexus",
            signingMode: .adHoc,
            signingIdentityLabel: "ad-hoc",
            expectedInstallPath: "/Users/test/Applications/Nexus.app",
            launchedFromExpectedPath: false
        )
    )

    #expect(detail.localizedCaseInsensitiveContains("ad-hoc"))
    #expect(detail.localizedCaseInsensitiveContains("NEXUS_CODESIGN_IDENTITY"))
}

@Test
func accessibilityDetailForStableDeniedBuildOmitsAdHocWarning() {
    let detail = PermissionInspector.accessibilityDetail(
        trusted: false,
        buildIdentity: BuildIdentityStatus(
            bundlePath: "/Users/test/Applications/Nexus.app",
            bundleIdentifier: "dev.nexusniri.Nexus",
            signingMode: .selfSigned,
            signingIdentityLabel: "Nexus Local Dev",
            expectedInstallPath: "/Users/test/Applications/Nexus.app",
            launchedFromExpectedPath: true
        )
    )

    #expect(detail.localizedCaseInsensitiveContains("blocked"))
    #expect(detail.localizedCaseInsensitiveContains("ad-hoc") == false)
}

@MainActor
@Test
func diagnosticsCenterLoadsRuntimeBuildMetadataFromBundledJSON() throws {
    let fixture = try TemporaryAppBundleFixture(
        metadata: """
        {
          "bundleIdentifier": "dev.nexusniri.Nexus",
          "signingMode": "selfSigned",
          "signingIdentityLabel": "Nexus Local Dev",
          "expectedInstallPath": "\(expanded(path: "~/Applications/Nexus.app"))",
          "buildTimestamp": "2026-03-13T12:00:00Z"
        }
        """
    )
    defer { fixture.remove() }

    let center = try DiagnosticsCenter(bundle: fixture.bundle())
    center.refresh(
        stateDirectory: URL(fileURLWithPath: "/tmp/nexus-state"),
        logDirectory: URL(fileURLWithPath: "/tmp/nexus-logs"),
        windowSnapshot: nil,
        adapterHealth: []
    )

    #expect(center.snapshot.buildIdentity.signingMode == .selfSigned)
    #expect(center.snapshot.buildIdentity.signingIdentityLabel == "Nexus Local Dev")
    #expect(center.snapshot.buildIdentity.bundleIdentifier == "dev.nexusniri.Nexus")
    #expect(center.snapshot.buildIdentity.expectedInstallPath == expanded(path: "~/Applications/Nexus.app"))
    #expect(center.snapshot.buildIdentity.launchedFromExpectedPath == false)
}

private func expanded(path: String) -> String {
    let expandedPath = (path as NSString).expandingTildeInPath
    return URL(fileURLWithPath: expandedPath).standardizedFileURL.path
}

private struct TemporaryAppBundleFixture {
    let rootURL: URL

    init(metadata: String) throws {
        let fileManager = FileManager.default
        let appURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("app")
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)

        try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>CFBundleIdentifier</key>
          <string>dev.nexusniri.Nexus</string>
          <key>CFBundleName</key>
          <string>Nexus</string>
        </dict>
        </plist>
        """.write(to: contentsURL.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        try metadata.write(
            to: resourcesURL.appendingPathComponent("dev-build-metadata.json"),
            atomically: true,
            encoding: .utf8
        )

        rootURL = appURL
    }

    func bundle() throws -> Bundle {
        guard let bundle = Bundle(url: rootURL) else {
            throw FixtureError.invalidBundle(rootURL.path)
        }
        return bundle
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private enum FixtureError: Error {
    case invalidBundle(String)
}
