import Foundation
import Testing
import SharedTypes
@testable import TetherAdapter

@Test
func defaultWebSocketURLCarriesToken() {
    let url = TetherAdapter.defaultWebSocketURL(
        from: URL(string: "http://127.0.0.1:3773")!,
        token: "secret"
    )

    #expect(url.scheme == "ws")
    #expect(url.absoluteString.contains("token=secret"))
}

@Test
func identityParsesProjectsAndThreadsFromSnapshotPayload() {
    let raw: [String: Any] = [
        "projects": [
            ["title": "Live Project"],
        ],
        "threads": [
            ["title": "Fix layout drift"],
        ],
    ]

    let identity = TetherAdapter.identity(from: raw)

    #expect(identity.projectTitles == ["Live Project"])
    #expect(identity.threadTitles == ["Fix layout drift"])
}

@Test
func healthCheckUsesInjectedTransport() async {
    let adapter = TetherAdapter(
        transport: { method, _ in
            #expect(method == "server.getConfig")
            return [
                "providers": [
                    ["available": true],
                ],
            ]
        }
    )

    let report = await adapter.healthCheck()

    #expect(report.health == .healthy)
}

@Test
func stageCarriesTargetFrameWhenProvided() async throws {
    let adapter = TetherAdapter(
        transport: { method, payload in
            #expect(method == "nexus.state.stage")
            #expect(payload["slotId"] as? String == "slot-1")
            #expect(payload["action"] as? String == VisibilityActionKind.show.rawValue)

            let targetFrame = payload["targetFrame"] as? [String: Double]
            #expect(targetFrame?["x"] == 12)
            #expect(targetFrame?["y"] == 24)
            #expect(targetFrame?["width"] == 640)
            #expect(targetFrame?["height"] == 720)
            return [:]
        }
    )

    let slot = Slot(
        id: "slot-1",
        workspaceID: "workspace-1",
        kind: .hybrid,
        label: "Tether",
        appBinding: AppBinding(bundleID: "com.t3tools.tether"),
        widthPolicy: SizePolicy(mode: .fraction, value: 0.4),
        layoutRole: .support,
        adapterID: "tether"
    )

    try await adapter.stage(
        slot: slot,
        action: VisibilityAction(
            slotID: slot.id,
            windowID: nil,
            kind: .show,
            targetFrame: RectValue(x: 12, y: 24, width: 640, height: 720)
        )
    )
}
