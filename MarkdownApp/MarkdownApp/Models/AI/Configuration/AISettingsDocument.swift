//
//  AISettingsDocument.swift
//  MarkdownApp
//
//  每个 Provider 拥有稳定 profile；默认值只在首次创建或明确 reset 时使用。
//

import Foundation

nonisolated struct AIProviderProfile: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let provider: AIProvider
    var baseURL: String
    var model: String
    var apiKey: String
    var preferences: AICapabilityPreferences
    var providerCapabilitySignals: [AIModelCapability: Bool]?
    var providerMetadataObservedAt: Date?
    let createdAt: Date
    var updatedAt: Date

    var config: AIConfig {
        AIConfig(
            provider: provider,
            baseURL: baseURL,
            model: model,
            apiKey: apiKey,
            preferences: preferences,
            profileID: id,
            providerCapabilitySignals: providerCapabilitySignals,
            providerMetadataObservedAt: providerMetadataObservedAt
        )
    }

    mutating func update(from config: AIConfig, at date: Date) {
        baseURL = config.baseURL
        model = config.model
        apiKey = config.apiKey
        preferences = config.preferences
        providerCapabilitySignals = config.providerCapabilitySignals
        providerMetadataObservedAt = config.providerMetadataObservedAt
        updatedAt = date
    }

    static func makeDefault(provider: AIProvider, at date: Date) -> AIProviderProfile {
        let manifest = AIProviderRegistry.manifest(for: provider)
        return AIProviderProfile(
            id: UUID(),
            provider: provider,
            baseURL: manifest.defaultBaseURL,
            model: manifest.defaultModel,
            apiKey: "",
            preferences: AICapabilityPreferences(),
            providerCapabilitySignals: nil,
            providerMetadataObservedAt: nil,
            createdAt: date,
            updatedAt: date
        )
    }
}

nonisolated struct AISettingsDocument: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    var activeProfileID: UUID
    var profiles: [AIProviderProfile]
    let migratedFromLegacy: Bool

    var activeProfile: AIProviderProfile? {
        profiles.first { $0.id == activeProfileID }
    }

    func profile(for provider: AIProvider) -> AIProviderProfile? {
        profiles.first { $0.provider == provider }
    }

    mutating func upsert(_ config: AIConfig, at date: Date) {
        if let index = profiles.firstIndex(where: { $0.provider == config.provider }) {
            profiles[index].update(from: config, at: date)
            activeProfileID = profiles[index].id
        } else {
            var profile = AIProviderProfile.makeDefault(provider: config.provider, at: date)
            profile.update(from: config, at: date)
            profiles.append(profile)
            activeProfileID = profile.id
        }
    }

    mutating func reset(provider: AIProvider, at date: Date) {
        let replacement = AIProviderProfile.makeDefault(provider: provider, at: date)
        if let index = profiles.firstIndex(where: { $0.provider == provider }) {
            profiles[index] = replacement
        } else {
            profiles.append(replacement)
        }
        activeProfileID = replacement.id
    }

    static func bootstrap(
        legacy: AIConfig?,
        at date: Date
    ) -> AISettingsDocument {
        let hasLegacy = legacy.map { config in
            !config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } == true
        var profiles = AIProvider.allCases.map {
            AIProviderProfile.makeDefault(provider: $0, at: date)
        }
        let activeProvider = hasLegacy ? legacy!.provider : .openAI
        if hasLegacy,
           let index = profiles.firstIndex(where: { $0.provider == legacy!.provider }) {
            profiles[index].update(from: legacy!, at: date)
        }
        let activeID = profiles.first(where: { $0.provider == activeProvider })!.id
        return AISettingsDocument(
            schemaVersion: currentSchemaVersion,
            activeProfileID: activeID,
            profiles: profiles,
            migratedFromLegacy: hasLegacy
        )
    }
}

nonisolated enum AISettingsDocumentError: Error, Equatable {
    case unsupportedSchema(Int)
    case missingActiveProfile
    case duplicateProvider(AIProvider)
}

nonisolated enum AISettingsDocumentValidator {
    static func validate(_ document: AISettingsDocument) throws {
        guard document.schemaVersion == AISettingsDocument.currentSchemaVersion else {
            throw AISettingsDocumentError.unsupportedSchema(document.schemaVersion)
        }
        guard document.activeProfile != nil else {
            throw AISettingsDocumentError.missingActiveProfile
        }
        for provider in AIProvider.allCases {
            let count = document.profiles.filter { $0.provider == provider }.count
            guard count <= 1 else { throw AISettingsDocumentError.duplicateProvider(provider) }
        }
    }
}
