//
//  AIConfig.swift
//  MarkdownApp
//
//  单一配置页面对应的原生 Provider 配置。Provider 显式保存；Base URL 只覆盖该
//  Provider 的 endpoint，不参与身份识别，也不会改变 wire contract。
//

import Foundation

nonisolated struct AIConfig: Codable, Equatable, Sendable {
    var provider: AIProvider
    var baseURL: String
    var model: String
    var apiKey: String
    var preferences: AICapabilityPreferences
    // Runtime capability scope and the selected catalog row travel with the saved
    // profile so an account-only model keeps the evidence the user actually saw.
    var profileID: UUID?
    var providerCapabilitySignals: [AIModelCapability: Bool]?
    var providerMetadataObservedAt: Date?

    init(
        provider: AIProvider = .openAI,
        baseURL: String,
        model: String,
        apiKey: String,
        preferences: AICapabilityPreferences = AICapabilityPreferences(),
        profileID: UUID? = nil,
        providerCapabilitySignals: [AIModelCapability: Bool]? = nil,
        providerMetadataObservedAt: Date? = nil
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.preferences = preferences
        self.profileID = profileID
        self.providerCapabilitySignals = providerCapabilitySignals
        self.providerMetadataObservedAt = providerMetadataObservedAt
    }

    static let empty = AIConfig(baseURL: "", model: "", apiKey: "")

    var validationIssues: [AIConfigValidationIssue] {
        AIProviderRegistry.validationIssues(for: self)
    }

    var isComplete: Bool { validationIssues.isEmpty }

    var resolvedProvider: ResolvedAIProviderConfiguration? {
        try? AIProviderRegistry.resolve(self)
    }

    var effectiveCapabilities: EffectiveProviderCapabilities? {
        resolvedProvider?.effectiveCapabilities
    }
}
