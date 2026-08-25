import Foundation

private struct LiveAuditModel: Codable {
    let id: String
    let displayName: String?
    let lifecycle: String
    let metadata: [String: String]
}

private struct LiveAuditSnapshot: Codable {
    let schemaVersion: Int
    let protocolEvidenceVersion: String
    let provider: String
    let endpoint: String
    let capturedAt: String
    let models: [LiveAuditModel]
}

@main
enum LiveModelSnapshotCLI {
    static func main() async throws {
        guard CommandLine.arguments.count == 3,
              let provider = AIProvider(rawValue: CommandLine.arguments[1])
        else {
            FileHandle.standardError.write(Data(
                "usage: live-model-snapshot <openAI|anthropic|gemini|kimi|glm> <output.json>\n".utf8
            ))
            exit(64)
        }
        guard let apiKey = ProcessInfo.processInfo.environment["AI_PROVIDER_API_KEY"],
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            FileHandle.standardError.write(Data(
                "AI_PROVIDER_API_KEY is required; it is never written to the snapshot.\n".utf8
            ))
            exit(64)
        }
        let manifest = AIProviderRegistry.manifest(for: provider)
        let baseURL = ProcessInfo.processInfo.environment["AI_PROVIDER_BASE_URL"]
            ?? manifest.defaultBaseURL
        let snapshot: AIModelCatalogSnapshot
        do {
            snapshot = try await AIModelCatalogService().fetch(for: AIConfig(
                provider: provider,
                baseURL: baseURL,
                model: manifest.defaultModel,
                apiKey: apiKey
            ))
        } catch AIModelCatalogError.unavailable {
            FileHandle.standardError.write(Data(
                "This provider has no verified first-party Models API. Use a reviewed manual snapshot.\n".utf8
            ))
            exit(69)
        }
        let formatter = ISO8601DateFormatter()
        let output = LiveAuditSnapshot(
            schemaVersion: 1,
            protocolEvidenceVersion: AIProviderRegistry.protocolEvidenceVersion,
            provider: provider.rawValue,
            endpoint: AIModelCatalogScope.normalizedEndpoint(baseURL),
            capturedAt: formatter.string(from: snapshot.fetchedAt),
            models: snapshot.models.map { descriptor in
                LiveAuditModel(
                    id: descriptor.id,
                    displayName: descriptor.displayName,
                    lifecycle: descriptor.lifecycle.rawValue,
                    metadata: metadata(descriptor.metadata, formatter: formatter)
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(output)
        try data.write(
            to: URL(fileURLWithPath: CommandLine.arguments[2]),
            options: .atomic
        )
        print("Captured \(output.models.count) sanitized model records for \(provider.rawValue).")
    }

    private static func metadata(
        _ value: AIModelProviderMetadata,
        formatter: ISO8601DateFormatter
    ) -> [String: String] {
        var result = value.additionalFields
        if let createdAt = value.createdAt { result["createdAt"] = formatter.string(from: createdAt) }
        if let owner = value.owner { result["owner"] = owner }
        if let version = value.version { result["version"] = version }
        if let description = value.description { result["description"] = description }
        if let input = value.inputTokenLimit { result["inputTokenLimit"] = String(input) }
        if let output = value.outputTokenLimit { result["outputTokenLimit"] = String(output) }
        if let shutdownAt = value.shutdownAt { result["shutdownAt"] = formatter.string(from: shutdownAt) }
        if !value.generationMethods.isEmpty {
            result["generationMethods"] = value.generationMethods.sorted().joined(separator: ",")
        }
        for (capability, supported) in value.capabilitySignals {
            result["capability.\(capability.rawValue)"] = String(supported)
        }
        return result
    }
}
