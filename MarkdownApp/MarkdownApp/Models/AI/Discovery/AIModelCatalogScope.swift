import Foundation

nonisolated enum AIModelCatalogScope {
    static let legacyProfileID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    static func normalizedEndpoint(_ value: String) -> String {
        guard var components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return value.lowercased() }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.query = nil
        components.fragment = nil
        var path = components.path
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        components.path = path
        return components.string ?? value.lowercased()
    }
}

