import Foundation

nonisolated struct GeminiModelDiscoveryStrategy: AIModelDiscoveryStrategy {
    let provider = AIProvider.gemini
    let catalogPath = "/v1beta/models"

    func initialQueryItems() -> [URLQueryItem] {
        [URLQueryItem(name: "pageSize", value: "100")]
    }

    func queryItems(for cursor: AIModelDiscoveryCursor) -> [URLQueryItem] {
        initialQueryItems() + [URLQueryItem(name: cursor.name, value: cursor.value)]
    }

    func parse(_ data: Data, observedAt: Date) throws -> AIModelDiscoveryPage {
        let root = try AIModelDiscoveryParsing.object(data)
        guard let values = root["models"] as? [[String: Any]] else {
            throw AIModelCatalogError.invalidResponse
        }
        let models = values.compactMap { value -> AIModelDescriptor? in
            let resourceName = AIModelDiscoveryParsing.string(value["name"])
            guard let id = AIModelDiscoveryParsing.string(value["baseModelId"])
                ?? resourceName?.replacingOccurrences(of: "models/", with: "")
            else { return nil }
            // Gemini 官方目录声明 generation methods；字段缺失保持 unknown，不能当成可生成。
            let methods = value["supportedGenerationMethods"] as? [String] ?? ["unknown"]
            var signals: [AIModelCapability: Bool] = [:]
            if let flag = AIModelDiscoveryParsing.explicitBool(value["thinking"]) {
                signals[.reasoning] = flag
            }
            let metadata = AIModelProviderMetadata(
                version: AIModelDiscoveryParsing.string(value["version"]),
                description: AIModelDiscoveryParsing.string(value["description"]),
                inputTokenLimit: AIModelDiscoveryParsing.integer(value["inputTokenLimit"]),
                outputTokenLimit: AIModelDiscoveryParsing.integer(value["outputTokenLimit"]),
                generationMethods: methods,
                capabilitySignals: signals,
                additionalFields: resourceName.map { ["resourceName": $0] } ?? [:]
            )
            return AIModelDiscoveryParsing.descriptor(
                id: id,
                displayName: AIModelDiscoveryParsing.string(value["displayName"]),
                metadata: metadata,
                observedAt: observedAt
            )
        }
        let token = AIModelDiscoveryParsing.string(root["nextPageToken"])
        return AIModelDiscoveryPage(
            models: models,
            nextCursor: token.map { AIModelDiscoveryCursor(name: "pageToken", value: $0) }
        )
    }
}
