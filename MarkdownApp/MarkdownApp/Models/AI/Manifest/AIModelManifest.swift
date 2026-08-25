//
//  AIModelManifest.swift
//  MarkdownApp
//
//  Bundle 内声明式模型治理数据。这里只描述型号、家族、能力和安全策略标识；
//  endpoint、鉴权、request/stream/tool/file wire contract 仍由强类型 Swift 拥有。
//

import Foundation

nonisolated enum AIModelLifecycle: String, Codable, Equatable, Sendable {
    case active
    case deprecated
    case shutdown
}

nonisolated enum AIModelCapability: String, Codable, CaseIterable, Equatable, Sendable {
    case writing
    case reasoning
    case nativeWebSearch
    case imageInput
    case pdfInput
    case genericFileInput
    case uploadedFile
    case fileExtraction
    case fileSearch
}

nonisolated enum AIManifestCapabilityState: String, Codable, Equatable, Sendable {
    case supported
    case unsupported
}

nonisolated struct AIManifestModel: Codable, Equatable, Sendable {
    let id: String
    let aliases: [String]
    let lifecycle: AIModelLifecycle
    let capabilities: [String: AIManifestCapabilityState]
    let strategies: [String: String]
}

nonisolated struct AIManifestFamily: Codable, Equatable, Sendable {
    let id: String
    let prefixes: [String]
    let excludedFragments: [String]
    let capabilities: [String: AIManifestCapabilityState]
    let strategies: [String: String]
}

nonisolated struct AIManifestProvider: Codable, Equatable, Sendable {
    let provider: AIProvider
    let verifiedAt: String
    let defaultBaseURL: String
    let defaultModel: String
    let protocolStrategy: String
    let discoveryStrategy: String
    let providerCapabilities: [String: AIManifestCapabilityState]
    let models: [AIManifestModel]
    let families: [AIManifestFamily]

    var documentedModelIDs: [String] { models.map(\.id).sorted() }

    func canonicalModelID(for value: String) -> String {
        let normalized = Self.normalized(value)
        return models.first(where: {
            Self.normalized($0.id) == normalized
                || $0.aliases.contains(where: { Self.normalized($0) == normalized })
        })?.id ?? value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func exactState(
        for capability: AIModelCapability,
        model: String
    ) -> AIManifestCapabilityState? {
        let canonical = Self.normalized(canonicalModelID(for: model))
        return models.first(where: { Self.normalized($0.id) == canonical })?
            .capabilities[capability.rawValue]
    }

    func familyState(
        for capability: AIModelCapability,
        model: String
    ) -> AIManifestCapabilityState? {
        matchingFamilies(model: model)
            .compactMap { $0.capabilities[capability.rawValue] }
            .first
    }

    func providerState(for capability: AIModelCapability) -> AIManifestCapabilityState? {
        providerCapabilities[capability.rawValue]
    }

    func strategyID(key: String, model: String) -> String? {
        let canonical = Self.normalized(canonicalModelID(for: model))
        if let exact = models.first(where: { Self.normalized($0.id) == canonical })?
            .strategies[key] {
            return exact
        }
        return matchingFamilies(model: model).compactMap { $0.strategies[key] }.first
    }

    func recognizes(model: String) -> Bool {
        let canonical = Self.normalized(canonicalModelID(for: model))
        return models.contains(where: { Self.normalized($0.id) == canonical })
            || !matchingFamilies(model: model).isEmpty
    }

    func lifecycle(model: String) -> AIModelLifecycle? {
        let canonical = Self.normalized(canonicalModelID(for: model))
        return models.first(where: { Self.normalized($0.id) == canonical })?.lifecycle
    }

    func supportsWriting(model: String) -> Bool {
        providerState(for: .writing) == .supported
            || exactState(for: .writing, model: model) == .supported
            || familyState(for: .writing, model: model) == .supported
    }

    func legacySupport(for capability: AIModelCapability) -> CapabilitySupport {
        if providerState(for: capability) == .supported { return .supported }
        let exactIDs = models.compactMap { model in
            model.capabilities[capability.rawValue] == .supported ? model.id : nil
        }
        let families = families.filter {
            $0.capabilities[capability.rawValue] == .supported
        }
        guard !exactIDs.isEmpty || !families.isEmpty else { return .unsupported }
        return .conditional(ModelCapabilityRule(
            exactIDs: exactIDs,
            variantPrefixes: families.flatMap(\.prefixes),
            excludedFragments: families.flatMap(\.excludedFragments)
        ))
    }

    private func matchingFamilies(model: String) -> [AIManifestFamily] {
        let normalized = Self.normalized(canonicalModelID(for: model))
        return families.filter { family in
            !family.excludedFragments.contains(where: {
                normalized.contains(Self.normalized($0))
            }) && family.prefixes.contains(where: {
                normalized.hasPrefix(Self.normalized($0))
            })
        }
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

nonisolated struct AIModelGovernanceManifest: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let contentVersion: String
    let protocolEvidenceVersion: String
    let providers: [AIManifestProvider]

    func provider(_ id: AIProvider) -> AIManifestProvider? {
        providers.first { $0.provider == id }
    }
}

nonisolated enum AIModelManifestError: Error, Equatable {
    case missingResource
    case unsupportedSchema(Int)
    case missingProvider(String)
    case duplicateProvider(String)
    case duplicateModel(String)
    case duplicateAlias(String)
    case invalidDefault(String)
    case unknownCapability(String)
    case unknownProtocolStrategy(String)
    case unknownDiscoveryStrategy(String)
    case unknownModelStrategy(String)
}

nonisolated enum AIModelManifestValidator {
    private static let protocols = Set([
        "openAIResponses", "anthropicMessages", "geminiInteractions", "kimiChat", "glmChat"
    ])
    private static let discovery = Set([
        "openAIList", "anthropicList", "geminiList", "kimiList", "unavailable"
    ])
    private static let modelStrategies = Set([
        "anthropicAdaptiveThinking", "kimiThinkingToggle", "kimiReasoningEffort",
        "glmAlwaysOnReasoning"
    ])

    static func validate(_ manifest: AIModelGovernanceManifest) throws {
        guard manifest.schemaVersion == 1 else {
            throw AIModelManifestError.unsupportedSchema(manifest.schemaVersion)
        }
        let providerIDs = manifest.providers.map(\.provider.rawValue)
        guard Set(providerIDs).count == providerIDs.count else {
            throw AIModelManifestError.duplicateProvider(providerIDs.joined(separator: ","))
        }
        for provider in AIProvider.allCases where manifest.provider(provider) == nil {
            throw AIModelManifestError.missingProvider(provider.rawValue)
        }
        for provider in manifest.providers {
            guard protocols.contains(provider.protocolStrategy) else {
                throw AIModelManifestError.unknownProtocolStrategy(provider.protocolStrategy)
            }
            guard discovery.contains(provider.discoveryStrategy) else {
                throw AIModelManifestError.unknownDiscoveryStrategy(provider.discoveryStrategy)
            }
            let modelIDs = provider.models.map { $0.id.lowercased() }
            guard Set(modelIDs).count == modelIDs.count else {
                throw AIModelManifestError.duplicateModel(provider.provider.rawValue)
            }
            var aliases = Set<String>()
            for model in provider.models {
                for alias in model.aliases.map({ $0.lowercased() }) {
                    guard aliases.insert(alias).inserted, !modelIDs.contains(alias) else {
                        throw AIModelManifestError.duplicateAlias(alias)
                    }
                }
                try validateCapabilities(model.capabilities)
                try validateStrategies(model.strategies)
            }
            for family in provider.families {
                try validateCapabilities(family.capabilities)
                try validateStrategies(family.strategies)
            }
            try validateCapabilities(provider.providerCapabilities)
            guard provider.recognizes(model: provider.defaultModel) else {
                throw AIModelManifestError.invalidDefault(provider.provider.rawValue)
            }
        }
    }

    private static func validateCapabilities(
        _ capabilities: [String: AIManifestCapabilityState]
    ) throws {
        for key in capabilities.keys where AIModelCapability(rawValue: key) == nil {
            throw AIModelManifestError.unknownCapability(key)
        }
    }

    private static func validateStrategies(_ strategies: [String: String]) throws {
        for value in strategies.values where !modelStrategies.contains(value) {
            throw AIModelManifestError.unknownModelStrategy(value)
        }
    }
}

nonisolated enum AIModelManifestLoader {
    static func decode(_ data: Data) throws -> AIModelGovernanceManifest {
        let manifest = try JSONDecoder().decode(AIModelGovernanceManifest.self, from: data)
        try AIModelManifestValidator.validate(manifest)
        return manifest
    }

    static func loadDefault() throws -> AIModelGovernanceManifest {
        if let override = ProcessInfo.processInfo.environment["AI_PROVIDER_MANIFEST_PATH"] {
            return try decode(Data(contentsOf: URL(fileURLWithPath: override)))
        }
        let candidates = [
            // Xcode's file-system-synchronized groups flatten ordinary resources
            // into the app bundle, even when the source lives under AIProviders/.
            Bundle.main.url(
                forResource: "manifest-v1",
                withExtension: "json"
            ),
            Bundle.main.url(
                forResource: "manifest-v1",
                withExtension: "json",
                subdirectory: "AIProviders"
            ),
            Bundle.main.url(
                forResource: "manifest-v1",
                withExtension: "json",
                subdirectory: "Resources/AIProviders"
            ),
            sourceResourceURL()
        ]
        guard let url = candidates.compactMap({ $0 }).first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else { throw AIModelManifestError.missingResource }
        return try decode(Data(contentsOf: url))
    }

    private static func sourceResourceURL() -> URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        return root
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("AIProviders", isDirectory: true)
            .appendingPathComponent("manifest-v1.json")
    }
}

nonisolated enum AIModelManifestRepository {
    static let shared: AIModelGovernanceManifest = {
        do { return try AIModelManifestLoader.loadDefault() }
        catch { preconditionFailure("Invalid bundled AI Provider Manifest: \(error)") }
    }()
}
