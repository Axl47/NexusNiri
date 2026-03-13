import AppKit
import Foundation
import AdapterBus
import SharedTypes

public final class GenericAXAdapter: @unchecked Sendable, NexusAdapter {
    public let id = "generic-ax"
    public let supportedBundleIDs: [String] = []

    public init() {}

    public func discover(in snapshot: WindowRegistrySnapshot) async -> [WindowCandidate] {
        snapshot.windows
    }

    public func activate(slot: Slot) async throws {
        guard let bundleID = slot.appBinding?.bundleID,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            throw NexusError.notFound("No running app found for \(slot.label).")
        }
        app.activate()
    }

    public func stage(slot: Slot, action: VisibilityAction) async throws {
        _ = (slot, action)
    }

    public func park(slot: Slot) async throws {
        _ = slot
    }

    public func captureState(for slot: Slot) async throws -> AdapterState? {
        AdapterState(adapterID: id, slotID: slot.id, health: .healthy, payload: ["label": slot.label])
    }

    public func restoreState(for slot: Slot, state: AdapterState?) async throws -> RuntimeBinding? {
        _ = slot
        guard let state else { return nil }
        return RuntimeBinding(matchConfidence: state.health == .healthy ? 0.5 : 0.2)
    }

    public func openTarget(for slot: Slot) async throws {
        guard let bundleID = slot.appBinding?.bundleID else {
            throw NexusError.invalidState("No bundle identifier is configured for \(slot.label).")
        }

        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                throw NexusError.notFound("No installed app found for bundle ID \(bundleID).")
            }

            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            return
        }

        try await activate(slot: slot)
    }

    public func healthCheck() async -> AdapterHealthReport {
        AdapterHealthReport(
            adapterID: id,
            health: AXIsProcessTrusted() ? .healthy : .degraded,
            detail: AXIsProcessTrusted()
                ? "Accessibility is available for generic window coordination."
                : "Accessibility is not granted, so generic adapter actions are limited."
        )
    }

    public func serializeState(_ state: AdapterState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(state)
    }
}
