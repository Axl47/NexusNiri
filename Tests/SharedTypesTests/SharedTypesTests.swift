import Foundation
import Testing
@testable import SharedTypes

@Test
func workspaceCodableRoundTripPreservesPrimaryFields() throws {
    let workspace = Workspace(
        name: "API",
        activeSlotID: "slot-1",
        slotOrder: ["slot-1"],
        layoutState: LayoutState(activeIndex: 0, scrollAnchor: 32, centeredSlotID: "slot-1"),
        slots: [
            Slot(
                id: "slot-1",
                workspaceID: "workspace-1",
                kind: .externalWindow,
                label: "Editor",
                appBinding: AppBinding(bundleID: "com.microsoft.VSCode"),
                widthPolicy: SizePolicy(mode: .fraction, value: 0.55),
                layoutRole: .primary
            ),
        ]
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(workspace)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(Workspace.self, from: data)

    #expect(decoded.name == "API")
    #expect(decoded.slotOrder == ["slot-1"])
    #expect(decoded.slots.first?.label == "Editor")
    #expect(decoded.layoutState.scrollAnchor == 32)
}
