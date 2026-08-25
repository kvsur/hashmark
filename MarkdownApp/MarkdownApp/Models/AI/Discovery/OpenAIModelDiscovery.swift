import Foundation

nonisolated struct OpenAIModelDiscoveryStrategy: AIModelDiscoveryStrategy {
    let provider = AIProvider.openAI
    let catalogPath = "/v1/models"

    func parse(_ data: Data, observedAt: Date) throws -> AIModelDiscoveryPage {
        let root = try AIModelDiscoveryParsing.object(data)
        guard let values = root["data"] as? [[String: Any]] else {
            throw AIModelCatalogError.invalidResponse
        }
        let models = values.compactMap { value -> AIModelDescriptor? in
            guard let id = AIModelDiscoveryParsing.string(value["id"]) else { return nil }
            let shutdown = AIModelDiscoveryParsing.date(value["shutdown_date"])
            let metadata = AIModelProviderMetadata(
                createdAt: AIModelDiscoveryParsing.date(value["created"]),
                owner: AIModelDiscoveryParsing.string(value["owned_by"]),
                shutdownAt: shutdown
            )
            return AIModelDiscoveryParsing.descriptor(
                id: id,
                metadata: metadata,
                lifecycle: shutdown == nil ? .active : .shutdown,
                observedAt: observedAt
            )
        }
        return AIModelDiscoveryPage(models: models, nextCursor: nil)
    }
}

