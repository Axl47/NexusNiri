import Foundation
import SharedTypes

public final class AdapterRegistry: @unchecked Sendable {
    private var adaptersByID: [String: any NexusAdapter] = [:]

    public init() {}

    public func register(_ adapter: any NexusAdapter) {
        adaptersByID[adapter.id] = adapter
    }

    public func adapter(for slot: Slot) -> (any NexusAdapter)? {
        if let adapterID = slot.adapterID, let adapter = adaptersByID[adapterID] {
            return adapter
        }

        if let bundleID = slot.appBinding?.bundleID,
           let matchingAdapter = adaptersByID.values.first(where: { $0.supportedBundleIDs.contains(bundleID) }) {
            return matchingAdapter
        }

        return adaptersByID["generic-ax"]
    }

    public func allAdapters() -> [any NexusAdapter] {
        adaptersByID.values.sorted { $0.id < $1.id }
    }

    public func healthReports() async -> [AdapterHealthReport] {
        var reports: [AdapterHealthReport] = []
        for adapter in allAdapters() {
            let report = await adapter.healthCheck()
            reports.append(report)
        }
        return reports
    }
}
