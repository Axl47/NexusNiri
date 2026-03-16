import Foundation
import SharedTypes

struct SlotPresetCatalog {
    struct SlotPreset: Codable, Equatable, Sendable {
        let bundleID: String
        let defaultLabel: String
        let kind: SlotKind
        let widthPolicy: SizePolicy
        let layoutRole: LayoutRole
        let warmPreference: WarmPreference
        let adapterID: String?
        let adapterHints: [String: String]
    }

    private let presetsByBundleID: [String: SlotPreset]

    init(bundle: Bundle = AppBootstrap.resourceBundle) {
        let presets = Self.loadPresets(from: bundle)
        presetsByBundleID = Dictionary(uniqueKeysWithValues: presets.compactMap { preset in
            guard let bundleID = Self.canonicalBundleID(preset.bundleID) else {
                return nil
            }
            return (bundleID, preset)
        })
    }

    func preset(for bundleID: String?) -> SlotPreset? {
        guard let bundleID = Self.canonicalBundleID(bundleID) else {
            return nil
        }
        return presetsByBundleID[bundleID]
    }

    private static func loadPresets(from bundle: Bundle) -> [SlotPreset] {
        guard let url = bundle.url(forResource: "slot-presets", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return []
        }

        let decoder = JSONDecoder()
        return (try? decoder.decode([SlotPreset].self, from: data)) ?? []
    }

    static func canonicalBundleID(_ bundleID: String?) -> String? {
        guard let bundleID = bundleID?.lowercased(), bundleID.isEmpty == false else {
            return nil
        }

        switch bundleID {
        case "dev.tether.desktop",
             "com.t3tools.tether.dev",
             "com.t3tools.tether-dev":
            return "com.t3tools.tether"
        case let bundleID where bundleID.hasPrefix("dev.tether.desktop."):
            return "com.t3tools.tether"
        default:
            return bundleID
        }
    }
}
