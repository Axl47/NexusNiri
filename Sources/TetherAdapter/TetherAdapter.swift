import Foundation
import AdapterBus
import SharedTypes

public struct TetherIdentity: Equatable, Sendable {
    public var projectTitles: [String]
    public var threadTitles: [String]

    public init(projectTitles: [String], threadTitles: [String]) {
        self.projectTitles = projectTitles
        self.threadTitles = threadTitles
    }
}

public final class TetherAdapter: NexusAdapter {
    public typealias Transport = (_ method: String, _ payload: [String: Any]) async throws -> Any

    public let id = "tether"
    public let supportedBundleIDs = ["dev.tether.desktop"]

    public let baseURL: URL
    public let webSocketURL: URL

    private let token: String?
    private let transport: Transport

    public init(
        baseURL: URL = URL(string: "http://127.0.0.1:3773")!,
        webSocketURL: URL? = nil,
        token: String? = nil,
        transport: Transport? = nil
    ) {
        self.baseURL = baseURL
        self.webSocketURL = webSocketURL ?? TetherAdapter.defaultWebSocketURL(from: baseURL, token: token)
        self.token = token
        self.transport = transport ?? TetherAdapter.makeLiveTransport(url: self.webSocketURL)
    }

    public func discover(in snapshot: WindowRegistrySnapshot) async -> [WindowCandidate] {
        snapshot.windows.filter { candidate in
            candidate.bundleID == "dev.tether.desktop" || candidate.appName.localizedCaseInsensitiveContains("tether")
        }
    }

    public func activate(slot: Slot) async throws {
        _ = try await transport("nexus.bringToFront", ["slotId": slot.id])
    }

    public func stage(slot: Slot, action: VisibilityAction) async throws {
        _ = try await transport(
            "nexus.state.stage",
            [
                "slotId": slot.id,
                "action": action.kind.rawValue,
            ]
        )
    }

    public func park(slot: Slot) async throws {
        _ = try await transport("nexus.state.park", ["slotId": slot.id])
    }

    public func captureState(for slot: Slot) async throws -> AdapterState? {
        let snapshot = try await transport("orchestration.getSnapshot", [:])
        let identity = Self.identity(from: snapshot)
        return AdapterState(
            adapterID: id,
            slotID: slot.id,
            health: .healthy,
            payload: [
                "projectTitles": identity.projectTitles.joined(separator: " • "),
                "threadTitles": identity.threadTitles.joined(separator: " • "),
            ]
        )
    }

    public func restoreState(for slot: Slot, state: AdapterState?) async throws -> RuntimeBinding? {
        guard let state else { return nil }
        _ = try await transport(
            "nexus.state.restore",
            [
                "slotId": slot.id,
                "state": state.payload,
            ]
        )
        return RuntimeBinding(matchConfidence: 0.9, state: .recovering, lastSeenAt: .now)
    }

    public func openTarget(for slot: Slot) async throws {
        _ = try await transport(
            "nexus.openTarget",
            [
                "slotId": slot.id,
                "bundleId": slot.appBinding?.bundleID ?? "dev.tether.desktop",
            ]
        )
    }

    public func healthCheck() async -> AdapterHealthReport {
        do {
            let config = try await transport("server.getConfig", [:])
            let providers = (Self.dictionary(config)?["providers"] as? [[String: Any]]) ?? []
            let healthyProviders = providers.filter { ($0["available"] as? Bool) == true }
            let health: AdapterHealth = healthyProviders.isEmpty ? .degraded : .healthy
            let detail = healthyProviders.isEmpty
                ? "Connected to Tether, but no provider is currently marked available."
                : "Connected to Tether with \(healthyProviders.count) available provider(s)."
            return AdapterHealthReport(adapterID: id, health: health, detail: detail)
        } catch {
            return AdapterHealthReport(
                adapterID: id,
                health: .unavailable,
                detail: "Tether WebSocket unavailable at \(webSocketURL.absoluteString): \(error.localizedDescription)"
            )
        }
    }

    public func serializeState(_ state: AdapterState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(state)
    }

    public static func defaultWebSocketURL(from baseURL: URL, token: String?) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.scheme = (components.scheme == "https") ? "wss" : "ws"
        if let token, !token.isEmpty {
            components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "token", value: token)]
        }
        return components.url ?? baseURL
    }

    public static func identity(from rawResponse: Any) -> TetherIdentity {
        let dictionary = dictionary(rawResponse)
        let projects = (dictionary?["projects"] as? [[String: Any]] ?? [])
            .compactMap { $0["title"] as? String }
        let threads = (dictionary?["threads"] as? [[String: Any]] ?? [])
            .compactMap { $0["title"] as? String }

        return TetherIdentity(projectTitles: projects, threadTitles: threads)
    }

    static func dictionary(_ value: Any) -> [String: Any]? {
        if let dictionary = value as? [String: Any] {
            return dictionary
        }
        if let data = value as? Data {
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        return nil
    }

    private static func makeLiveTransport(url: URL) -> Transport {
        { method, payload in
            let session = URLSession(configuration: .default)
            let task = session.webSocketTask(with: url)
            task.resume()
            defer {
                task.cancel(with: .normalClosure, reason: nil)
            }

            let requestID = UUID().uuidString
            var body = payload
            body["_tag"] = method
            let envelope: [String: Any] = [
                "id": requestID,
                "body": body,
            ]
            let requestData = try JSONSerialization.data(withJSONObject: envelope, options: [])
            try await task.send(.data(requestData))

            while true {
                let message = try await task.receive()
                let messageData: Data
                switch message {
                case .data(let data):
                    messageData = data
                case .string(let text):
                    messageData = Data(text.utf8)
                @unknown default:
                    continue
                }

                guard let response = try JSONSerialization.jsonObject(with: messageData) as? [String: Any] else {
                    continue
                }

                if response["type"] as? String == "push" {
                    continue
                }

                if let responseID = response["id"] as? String, responseID == requestID {
                    if let error = response["error"] as? [String: Any],
                       let message = error["message"] as? String {
                        throw NexusError.network(message)
                    }
                    return response["result"] ?? [:]
                }
            }
        }
    }
}
