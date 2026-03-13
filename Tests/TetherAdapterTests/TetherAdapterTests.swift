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
