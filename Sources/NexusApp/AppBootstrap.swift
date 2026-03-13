import Foundation
import SharedTypes

enum AppBootstrap {
    static func defaultWorkspaces() -> [Workspace] {
        guard let url = Bundle.module.url(forResource: "default-workspaces", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Workspace].self, from: data)) ?? []
    }
}
