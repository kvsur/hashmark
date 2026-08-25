import Foundation

nonisolated struct AnthropicModelDiscoveryStrategy: AIModelDiscoveryStrategy {
    let provider = AIProvider.anthropic
    let catalogPath = "/v1/models"

    func initialQueryItems() -> [URLQueryItem] {
        [URLQueryItem(name: "limit", value: "100")]
    }

    func queryItems(for cursor: AIModelDiscoveryCursor) -> [URLQueryItem] {
        initialQueryItems() + [URLQueryItem(name: cursor.name, value: cursor.value)]
    }

    func parse(_ data: Data, observedAt: Date) throws -> AIModelDiscoveryPage {
        let root = try AIModelDiscoveryParsing.object(data)
        guard let values = root["data"] as? [[String: Any]] else {
            throw AIModelCatalogError.invalidResponse
        }
        let models = values.compactMap { value -> AIModelDescriptor? in
            guard let id = AIModelDiscoveryParsing.string(value["id"]) else { return nil }
            let raw = value["capabilities"] as? [String: Any] ?? [:]
            var signals: [AIModelCapability: Bool] = [:]
            if let flag = AIModelDiscoveryParsing.explicitBool(raw["image_input"]) {
                signals[.imageInput] = flag
            }
            if let flag = AIModelDiscoveryParsing.explicitBool(raw["pdf_input"]) {
                signals[.pdfInput] = flag
                signals[.genericFileInput] = flag
            }
            if let flag = AIModelDiscoveryParsing.explicitBool(raw["thinking"]) {
                signals[.reasoning] = flag
            }
            let metadata = AIModelProviderMetadata(
                createdAt: AIModelDiscoveryParsing.date(value["created_at"]),
                description: AIModelDiscoveryParsing.string(value["description"]),
                capabilitySignals: signals,
                additionalFields: [
                    "type": AIModelDiscoveryParsing.string(value["type"]) ?? "model"
                ]
            )
            return AIModelDiscoveryParsing.descriptor(
                id: id,
                displayName: AIModelDiscoveryParsing.string(value["display_name"]),
                metadata: metadata,
                observedAt: observedAt
            )
        }
        let hasMore = AIModelDiscoveryParsing.explicitBool(root["has_more"]) == true
        let lastID = AIModelDiscoveryParsing.string(root["last_id"])
        return AIModelDiscoveryPage(
            models: models,
            nextCursor: hasMore && lastID != nil
                ? AIModelDiscoveryCursor(name: "after_id", value: lastID!)
                : nil
        )
    }
}

