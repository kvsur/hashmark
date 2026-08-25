//
//  AIConfig.swift
//  MarkdownApp
//
//  单一配置页面对应的原生 Provider 配置。Provider 显式保存；Base URL 只覆盖该
//  Provider 的 endpoint，不参与身份识别，也不会改变 wire contract。
//

import Foundation

nonisolated struct AIConfig: Codable, Equatable {
    var provider: AIProvider
    var baseURL: String
    var model: String
    var apiKey: String
    var preferences: AICapabilityPreferences

    init(
        provider: AIProvider = .openAI,
        baseURL: String,
        model: String,
        apiKey: String,
        preferences: AICapabilityPreferences = AICapabilityPreferences()
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.preferences = preferences
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
