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

@Test
func workspaceCodableDefaultsMissingTargetingAndAutoAddFields() throws {
    let json = """
    {
      "id": "workspace-1",
      "name": "Main",
      "description": null,
      "profileID": null,
      "displayPolicy": "static",
      "preferredDisplayID": null,
      "activeSlotID": "slot-1",
      "slotOrder": ["slot-1"],
      "floatingSlotIDs": [],
      "layoutState": {
        "activeIndex": 0,
        "scrollAnchor": 0,
        "centeredSlotID": "slot-1",
        "visibleSlotIDs": ["slot-1"],
        "parkedSlotIDs": [],
        "geometryVersion": 1
      },
      "visibilityPolicy": {
        "defaultStrategy": "edgeSliver",
        "prefersHideForBackgroundApps": false,
        "keepsFloatsVisible": true,
        "revealAllShortcutEnabled": true
      },
      "residencyPolicy": {
        "hotSlotIDs": [],
        "warmSlotIDs": [],
        "coldLaunchAllowed": true
      },
      "assignmentRuleIDs": [],
      "adapterStateIDs": [],
      "snapshotIDs": [],
      "tags": [],
      "createdAt": "2026-03-14T23:00:00Z",
      "updatedAt": "2026-03-14T23:00:00Z",
      "slots": [
        {
          "id": "slot-1",
          "workspaceID": "workspace-1",
          "kind": "externalWindow",
          "label": "Editor",
          "appBinding": {
            "bundleID": "com.microsoft.VSCode",
            "preferredProcessStrategy": "reuse",
            "titleHints": [],
            "urlHints": [],
            "documentHints": [],
            "profileHint": null,
            "launchCommand": null,
            "adapterHints": {}
          },
          "widthPolicy": {
            "mode": "fraction",
            "value": 0.55,
            "minimum": null,
            "maximum": null
          },
          "heightPolicy": {
            "mode": "fill",
            "value": null,
            "minimum": null,
            "maximum": null
          },
          "layoutRole": "primary",
          "adapterID": null,
          "adapterStateID": null,
          "runtimeBinding": null,
          "lastKnownDisplayID": null,
          "pinned": false,
          "warmPreference": "warm",
          "createdAt": "2026-03-14T23:00:00Z",
          "updatedAt": "2026-03-14T23:00:00Z"
        }
      ]
    }
    """

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(Workspace.self, from: Data(json.utf8))

    #expect(decoded.autoAddPolicy == .disabled)
    #expect(decoded.slots.first?.targetingMode == .application)
}
