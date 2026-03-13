import AppKit
import ApplicationServices
import Foundation
import OSLog
import SharedTypes

@MainActor
public final class DiagnosticsCenter {
    public private(set) var snapshot: DiagnosticsSnapshot

    private let logger = Logger(subsystem: "dev.nexusniri.Nexus", category: "diagnostics")
    private let bundle: Bundle

    public init(
        initialSnapshot: DiagnosticsSnapshot = DiagnosticsSnapshot(),
        bundle: Bundle = .main
    ) {
        snapshot = initialSnapshot
        self.bundle = bundle
    }

    public func refresh(
        stateDirectory: URL,
        logDirectory: URL,
        windowSnapshot: WindowRegistrySnapshot?,
        adapterHealth: [AdapterHealthReport]
    ) {
        let buildIdentity = BuildIdentityLoader.load(from: bundle)
        let permissions = PermissionInspector.inspect(buildIdentity: buildIdentity)
        let notes = (windowSnapshot?.notes ?? []) + ["Logs at \(logDirectory.path)"]
        snapshot = DiagnosticsSnapshot(
            refreshedAt: .now,
            permissions: permissions,
            buildIdentity: buildIdentity,
            adapterHealth: adapterHealth,
            windows: windowSnapshot?.windows ?? [],
            notes: notes,
            stateDirectory: stateDirectory.path,
            logDirectory: logDirectory.path
        )
        logger.info("Diagnostics refreshed with \(self.snapshot.windows.count, privacy: .public) window(s).")
    }

    @discardableResult
    public func requestAccessibilityAccess() -> Bool {
        PermissionInspector.requestAccessibilityAccess()
    }

    public func openAccessibilitySettings() {
        guard
            let status = snapshot.permissions.first(where: { $0.kind == .accessibility }),
            let settingsURL = status.settingsURL,
            let url = URL(string: settingsURL)
        else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}

public enum PermissionInspector {
    public static func inspect(buildIdentity: BuildIdentityStatus = BuildIdentityStatus()) -> [PermissionStatus] {
        [
            accessibilityStatus(buildIdentity: buildIdentity),
            automationStatus(),
            screenRecordingStatus(),
        ]
    }

    @discardableResult
    public static func requestAccessibilityAccess() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func accessibilityDetail(
        trusted: Bool,
        buildIdentity: BuildIdentityStatus
    ) -> String {
        guard !trusted else {
            return "Accessibility access is enabled for the running Nexus.app."
        }

        if buildIdentity.signingMode == .adHoc {
            return "Window movement is blocked. This Nexus build is ad-hoc signed, so macOS will not keep a reliable Accessibility trust identity across rebuilds. Rebuild with NEXUS_CODESIGN_IDENTITY and launch the installed app path."
        }

        if let expectedInstallPath = buildIdentity.expectedInstallPath,
           !expectedInstallPath.isEmpty,
           buildIdentity.launchedFromExpectedPath == false {
            return "Window movement is blocked. Grant Accessibility to the installed Nexus.app and launch it from \(expectedInstallPath) so the trusted app path matches the running process."
        }

        return "Window movement is blocked until Accessibility is granted to the running Nexus.app."
    }

    private static func accessibilityStatus(buildIdentity: BuildIdentityStatus) -> PermissionStatus {
        let trusted = AXIsProcessTrusted()
        return PermissionStatus(
            kind: .accessibility,
            state: trusted ? .granted : .denied,
            detail: accessibilityDetail(trusted: trusted, buildIdentity: buildIdentity),
            settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
    }

    private static func automationStatus() -> PermissionStatus {
        PermissionStatus(
            kind: .automation,
            state: .unknown,
            detail: "Automation permission cannot be preflighted reliably. Nexus will prompt when an Apple Events action is attempted.",
            settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        )
    }

    private static func screenRecordingStatus() -> PermissionStatus {
        let granted = CGPreflightScreenCaptureAccess()
        return PermissionStatus(
            kind: .screenRecording,
            state: granted ? .granted : .notDetermined,
            detail: granted ? "Screen Recording is available for future preview surfaces." : "Optional for v1. Needed later for preview and portal features.",
            settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        )
    }
}

private enum BuildIdentityLoader {
    private static let metadataFileName = "dev-build-metadata"

    static func load(from bundle: Bundle) -> BuildIdentityStatus {
        let bundlePath = bundle.bundleURL.path
        let bundleIdentifier = bundle.bundleIdentifier ?? ""
        guard let metadataURL = bundle.url(forResource: metadataFileName, withExtension: "json"),
              let data = try? Data(contentsOf: metadataURL) else {
            return BuildIdentityStatus(
                bundlePath: bundlePath,
                bundleIdentifier: bundleIdentifier,
                signingMode: .unknown,
                signingIdentityLabel: nil,
                expectedInstallPath: nil,
                launchedFromExpectedPath: false,
                buildTimestamp: nil
            )
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let metadata = try? decoder.decode(DevBuildMetadata.self, from: data) else {
            return BuildIdentityStatus(
                bundlePath: bundlePath,
                bundleIdentifier: bundleIdentifier,
                signingMode: .unknown,
                signingIdentityLabel: nil,
                expectedInstallPath: nil,
                launchedFromExpectedPath: false,
                buildTimestamp: nil
            )
        }

        let expectedInstallPath = metadata.expectedInstallPath.map(expandAndStandardize(path:))
        let standardizedBundlePath = expandAndStandardize(path: bundlePath)
        let launchedFromExpectedPath = expectedInstallPath.map { $0 == standardizedBundlePath } ?? false

        return BuildIdentityStatus(
            bundlePath: standardizedBundlePath,
            bundleIdentifier: metadata.bundleIdentifier.isEmpty ? bundleIdentifier : metadata.bundleIdentifier,
            signingMode: metadata.signingMode,
            signingIdentityLabel: metadata.signingIdentityLabel,
            expectedInstallPath: expectedInstallPath,
            launchedFromExpectedPath: launchedFromExpectedPath,
            buildTimestamp: metadata.buildTimestamp
        )
    }

    private static func expandAndStandardize(path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }
}

private struct DevBuildMetadata: Codable {
    let bundleIdentifier: String
    let signingMode: BuildSigningMode
    let signingIdentityLabel: String?
    let expectedInstallPath: String?
    let buildTimestamp: Date?
}
