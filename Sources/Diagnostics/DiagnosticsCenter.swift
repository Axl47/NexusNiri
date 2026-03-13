import AppKit
import ApplicationServices
import Foundation
import OSLog
import SharedTypes

@MainActor
public final class DiagnosticsCenter {
    public private(set) var snapshot: DiagnosticsSnapshot

    private let logger = Logger(subsystem: "dev.nexusniri.Nexus", category: "diagnostics")

    public init(initialSnapshot: DiagnosticsSnapshot = DiagnosticsSnapshot()) {
        snapshot = initialSnapshot
    }

    public func refresh(
        stateDirectory: URL,
        logDirectory: URL,
        windowSnapshot: WindowRegistrySnapshot?,
        adapterHealth: [AdapterHealthReport]
    ) {
        let permissions = PermissionInspector.inspect()
        let notes = (windowSnapshot?.notes ?? []) + ["Logs at \(logDirectory.path)"]
        snapshot = DiagnosticsSnapshot(
            refreshedAt: .now,
            permissions: permissions,
            adapterHealth: adapterHealth,
            windows: windowSnapshot?.windows ?? [],
            notes: notes,
            stateDirectory: stateDirectory.path,
            logDirectory: logDirectory.path
        )
        logger.info("Diagnostics refreshed with \(self.snapshot.windows.count, privacy: .public) window(s).")
    }
}

public enum PermissionInspector {
    public static func inspect() -> [PermissionStatus] {
        [
            accessibilityStatus(),
            automationStatus(),
            screenRecordingStatus(),
        ]
    }

    private static func accessibilityStatus() -> PermissionStatus {
        let trusted = AXIsProcessTrusted()
        return PermissionStatus(
            kind: .accessibility,
            state: trusted ? .granted : .denied,
            detail: trusted ? "Accessibility access is enabled." : "Grant Accessibility so Nexus can discover and coordinate windows.",
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
