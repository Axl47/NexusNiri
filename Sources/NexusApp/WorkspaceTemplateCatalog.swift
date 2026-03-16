import Foundation
import SharedTypes

struct WorkspaceTemplateCatalog {
    struct TemplateSlot: Codable, Equatable, Sendable {
        let bundleID: String?
        let label: String?
        let titleHints: [String]
    }

    struct TemplateDefinition: Codable, Equatable, Identifiable, Sendable {
        let id: String
        let title: String
        let subtitle: String?
        let defaultName: String
        let description: String?
        let tags: [String]
        let slots: [TemplateSlot]
    }

    private let templates: [TemplateDefinition]
    private let presets: SlotPresetCatalog

    init(bundle: Bundle = AppBootstrap.resourceBundle, presets: SlotPresetCatalog = SlotPresetCatalog()) {
        self.templates = Self.loadTemplates(from: bundle)
        self.presets = presets
    }

    var options: [WorkspaceTemplateOption] {
        templates.map { template in
            WorkspaceTemplateOption(id: template.id, title: template.title, subtitle: template.subtitle)
        }
    }

    func instantiate(templateID: String, workspaceName: String? = nil, now: Date = .now) -> Workspace? {
        guard let template = templates.first(where: { $0.id == templateID }) else {
            return nil
        }

        let workspaceID = UUID().uuidString
        let slots = template.slots.compactMap { definition -> Slot? in
            let canonicalBundleID = SlotPresetCatalog.canonicalBundleID(definition.bundleID)
            let preset = presets.preset(for: canonicalBundleID)
            guard let bundleID = canonicalBundleID ?? preset?.bundleID else {
                return nil
            }

            return Slot(
                workspaceID: workspaceID,
                kind: preset?.kind ?? .externalWindow,
                targetingMode: .application,
                label: definition.label ?? preset?.defaultLabel ?? template.title,
                appBinding: AppBinding(
                    bundleID: bundleID,
                    titleHints: definition.titleHints,
                    adapterHints: preset?.adapterHints ?? [:]
                ),
                widthPolicy: preset?.widthPolicy ?? SizePolicy(mode: .fraction, value: 0.5, minimum: 400),
                layoutRole: preset?.layoutRole ?? .primary,
                adapterID: preset?.adapterID,
                warmPreference: preset?.warmPreference ?? .warm,
                createdAt: now,
                updatedAt: now
            )
        }

        let slotOrder = slots.map(\.id)
        let hotSlotIDs = slots.filter { $0.warmPreference == .hot }.map(\.id)
        let warmSlotIDs = slots.filter { $0.warmPreference == .warm }.map(\.id)
        let visibleSlotIDs = Array(slotOrder.prefix(2))
        let parkedSlotIDs = Array(slotOrder.dropFirst(2))

        return Workspace(
            id: workspaceID,
            name: (workspaceName?.isEmpty == false ? workspaceName : nil) ?? template.defaultName,
            description: template.description,
            activeSlotID: slotOrder.first,
            slotOrder: slotOrder,
            layoutState: LayoutState(
                activeIndex: 0,
                centeredSlotID: slotOrder.first,
                visibleSlotIDs: visibleSlotIDs,
                parkedSlotIDs: parkedSlotIDs
            ),
            residencyPolicy: ResidencyPolicy(
                hotSlotIDs: hotSlotIDs,
                warmSlotIDs: warmSlotIDs,
                coldLaunchAllowed: true
            ),
            tags: template.tags,
            createdAt: now,
            updatedAt: now,
            slots: slots
        )
    }

    private static func loadTemplates(from bundle: Bundle) -> [TemplateDefinition] {
        guard let url = bundle.url(forResource: "workspace-templates", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return []
        }

        let decoder = JSONDecoder()
        return (try? decoder.decode([TemplateDefinition].self, from: data)) ?? []
    }
}
