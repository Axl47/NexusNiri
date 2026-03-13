import Foundation
import SharedTypes

public actor JSONWorkspaceStore: WorkspaceStore {
    public nonisolated let stateDirectoryURL: URL
    public nonisolated let logDirectoryURL: URL

    private let stateFileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager

    public init(
        fileManager: FileManager = .default,
        baseDirectoryURL: URL? = nil,
        appFolderName: String = "Nexus"
    ) {
        self.fileManager = fileManager

        let rootURL = baseDirectoryURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent(appFolderName, isDirectory: true)

        stateDirectoryURL = rootURL
        logDirectoryURL = rootURL.appendingPathComponent("logs", isDirectory: true)
        stateFileURL = rootURL.appendingPathComponent("workspace-state.json", isDirectory: false)

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func loadState() async throws -> PersistedWorkspaceState {
        try ensureDirectoriesExist()

        guard fileManager.fileExists(atPath: stateFileURL.path) else {
            return .empty
        }

        let data = try Data(contentsOf: stateFileURL)
        return try decoder.decode(PersistedWorkspaceState.self, from: data)
    }

    public func saveState(_ state: PersistedWorkspaceState) async throws {
        try ensureDirectoriesExist()

        let data = try encoder.encode(state)
        try data.write(to: stateFileURL, options: [.atomic])
    }

    private func ensureDirectoriesExist() throws {
        try fileManager.createDirectory(at: stateDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)
    }
}
