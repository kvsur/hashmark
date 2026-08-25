import Foundation

nonisolated struct KimiModelDiscoveryStrategy: AIModelDiscoveryStrategy {
    let provider = AIProvider.kimi
    let catalogPath = "/v1/models"

    func parse(_ data: Data, observedAt: Date) throws -> AIModelDiscoveryPage {
        let root = try AIModelDiscoveryParsing.object(data)
        guard let values = root["data"] as? [[String: Any]] else {
            throw AIModelCatalogError.invalidResponse
        }
        let models = values.compactMap { value -> AIModelDescriptor? in
            guard let id = AIModelDiscoveryParsing.string(value["id"]) else { return nil }
            return AIModelDiscoveryParsing.descriptor(
                id: id,
                metadata: AIModelProviderMetadata(
                    createdAt: AIModelDiscoveryParsing.date(value["created"]),
                    owner: AIModelDiscoveryParsing.string(value["owned_by"])
                ),
                observedAt: observedAt
            )
        }
        return AIModelDiscoveryPage(models: models, nextCursor: nil)
    }
}

