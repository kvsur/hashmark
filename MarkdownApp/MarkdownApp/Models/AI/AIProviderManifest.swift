//
//  AIProviderManifest.swift
//  MarkdownApp
//
//  五家第一方 endpoint、鉴权、当前模型和原生工具机制的唯一事实源。
//  verifiedAt 必须随官方契约复核更新；模型列表接口只用于发现，不能自动证明高级能力。
//

import Foundation

nonisolated enum NativeProviderAuthentication: Equatable {
    case bearer
    case anthropic(apiVersion: String)
    case googleAPIKey
}

nonisolated enum NativeWebSearchMechanism: Equatable {
    case openAIHostedTool(type: String)
    case anthropicServerTool(version: String)
    case geminiGoogleSearch
    case kimiFormula(name: String, uri: String, requiresThinkingDisabled: Bool)
    case glmStandaloneAPI

    var automaticContinuationToolName: String? {
        if case .kimiFormula(let name, _, _) = self { name } else { nil }
    }

    var isNativeRequestMechanism: Bool { true }

    func requiresThinkingDisabled(for model: String) -> Bool {
        switch self {
        case .anthropicServerTool:
            // Anthropic 只允许 thinking 与 auto/none tool choice 组合；强制搜索时必须关闭。
            true
        case .kimiFormula(_, _, let required):
            // K3 始终思考并改用 reasoning_effort；K2.x 的 Formula 搜索仍需关闭 thinking。
            required && KimiModelContract.reasoningStyle(for: model) == .thinkingToggle
        default:
            false
        }
    }
}

nonisolated enum NativeFileMechanism: String, Hashable {
    case directInput
    case uploadReference
    case extraction
    case hostedRetrieval
}

nonisolated struct AIProviderManifest: Equatable {
    let provider: AIProvider
    let verifiedAt: String
    let defaultBaseURL: String
    let defaultModel: String
    let endpointPath: String
    let authentication: NativeProviderAuthentication
    let webSearch: NativeWebSearchMechanism
    let fileMechanisms: Set<NativeFileMechanism>
    let capabilities: ProviderCapabilities

    var documentedModelIDs: [String] {
        AIModelManifestRepository.shared.provider(provider)?.documentedModelIDs ?? []
    }
}

nonisolated struct ResolvedAIProviderConfiguration: Equatable {
    let manifest: AIProviderManifest
    let endpointURL: URL
    let baseURL: String
    let model: String
    let apiKey: String
    let effectiveCapabilities: EffectiveProviderCapabilities
    let profileID: UUID
    let providerCapabilitySignals: [AIModelCapability: Bool]
    let providerMetadataObservedAt: Date?
    let webSearchRequested: Bool
    let reasoningEffort: AIReasoningEffort

    var provider: AIProvider { manifest.provider }

    func modelStrategyID(key: String) -> String? {
        AIProviderRegistry.modelPolicy(for: provider).strategyID(key: key, model: model)
    }
}

nonisolated enum AIConfigValidationIssue: Error, Equatable {
    case missingBaseURL
    case missingModel
    case missingAPIKey
    case invalidBaseURL
    case unsupportedURLScheme
}

nonisolated enum AIProviderRegistry {
    static let manifestContentVersion = AIModelManifestRepository.shared.contentVersion
    static let protocolEvidenceVersion = AIModelManifestRepository.shared.protocolEvidenceVersion

    static let manifests: [AIProvider: AIProviderManifest] = [
        .openAI: AIProviderManifest(
            provider: .openAI,
            verifiedAt: data(for: .openAI).verifiedAt,
            defaultBaseURL: data(for: .openAI).defaultBaseURL,
            defaultModel: data(for: .openAI).defaultModel,
            endpointPath: "/v1/responses",
            authentication: .bearer,
            webSearch: .openAIHostedTool(type: "web_search"),
            fileMechanisms: [.directInput, .uploadReference, .hostedRetrieval],
            capabilities: capabilities(
                reasoning: support(.reasoning, provider: .openAI),
                search: support(.nativeWebSearch, provider: .openAI),
                image: support(.imageInput, provider: .openAI),
                pdf: support(.pdfInput, provider: .openAI),
                directFile: support(.genericFileInput, provider: .openAI),
                uploadedFile: support(.uploadedFile, provider: .openAI),
                fileSearch: support(.fileSearch, provider: .openAI)
            )
        ),
        .anthropic: AIProviderManifest(
            provider: .anthropic,
            verifiedAt: data(for: .anthropic).verifiedAt,
            defaultBaseURL: data(for: .anthropic).defaultBaseURL,
            defaultModel: data(for: .anthropic).defaultModel,
            endpointPath: "/v1/messages",
            authentication: .anthropic(apiVersion: "2023-06-01"),
            webSearch: .anthropicServerTool(version: "web_search_20250305"),
            fileMechanisms: [.directInput, .uploadReference],
            capabilities: capabilities(
                reasoning: support(.reasoning, provider: .anthropic),
                search: support(.nativeWebSearch, provider: .anthropic),
                image: support(.imageInput, provider: .anthropic),
                pdf: support(.pdfInput, provider: .anthropic),
                directFile: support(.genericFileInput, provider: .anthropic),
                uploadedFile: support(.uploadedFile, provider: .anthropic)
            )
        ),
        .gemini: AIProviderManifest(
            provider: .gemini,
            verifiedAt: data(for: .gemini).verifiedAt,
            defaultBaseURL: data(for: .gemini).defaultBaseURL,
            defaultModel: data(for: .gemini).defaultModel,
            endpointPath: "/v1beta/interactions",
            authentication: .googleAPIKey,
            webSearch: .geminiGoogleSearch,
            fileMechanisms: [.directInput, .uploadReference, .hostedRetrieval],
            capabilities: capabilities(
                reasoning: support(.reasoning, provider: .gemini),
                search: support(.nativeWebSearch, provider: .gemini),
                image: support(.imageInput, provider: .gemini),
                pdf: support(.pdfInput, provider: .gemini),
                directFile: support(.genericFileInput, provider: .gemini),
                uploadedFile: support(.uploadedFile, provider: .gemini),
                fileSearch: support(.fileSearch, provider: .gemini)
            )
        ),
        .kimi: AIProviderManifest(
            provider: .kimi,
            verifiedAt: data(for: .kimi).verifiedAt,
            defaultBaseURL: data(for: .kimi).defaultBaseURL,
            defaultModel: data(for: .kimi).defaultModel,
            endpointPath: "/v1/chat/completions",
            authentication: .bearer,
            webSearch: .kimiFormula(
                name: "web_search",
                uri: "moonshot/web-search:latest",
                requiresThinkingDisabled: true
            ),
            fileMechanisms: [.directInput, .uploadReference, .extraction],
            capabilities: capabilities(
                reasoning: support(.reasoning, provider: .kimi),
                // Formula 是 Provider 级工具；具体模型清单不应把用户已开启的搜索静默移除。
                search: support(.nativeWebSearch, provider: .kimi),
                image: support(.imageInput, provider: .kimi),
                // Files/file-extract 先解析为文本，再交给聊天模型，属于 Provider 级能力。
                pdf: support(.pdfInput, provider: .kimi),
                directFile: support(.genericFileInput, provider: .kimi),
                uploadedFile: support(.uploadedFile, provider: .kimi),
                extraction: support(.fileExtraction, provider: .kimi)
            )
        ),
        .glm: AIProviderManifest(
            provider: .glm,
            verifiedAt: data(for: .glm).verifiedAt,
            defaultBaseURL: data(for: .glm).defaultBaseURL,
            defaultModel: data(for: .glm).defaultModel,
            endpointPath: "/api/paas/v4/chat/completions",
            authentication: .bearer,
            webSearch: .glmStandaloneAPI,
            fileMechanisms: [.directInput, .uploadReference],
            capabilities: capabilities(
                reasoning: support(.reasoning, provider: .glm),
                search: support(.nativeWebSearch, provider: .glm),
                image: support(.imageInput, provider: .glm),
                pdf: support(.pdfInput, provider: .glm),
                directFile: support(.genericFileInput, provider: .glm),
                uploadedFile: support(.uploadedFile, provider: .glm)
            )
        )
    ]

    static func manifest(for provider: AIProvider) -> AIProviderManifest {
        manifests[provider]!
    }

    static func modelPolicy(for provider: AIProvider) -> AIManifestProvider {
        data(for: provider)
    }

    static func validationIssues(for config: AIConfig) -> [AIConfigValidationIssue] {
        var issues: [AIConfigValidationIssue] = []
        if trimmed(config.baseURL).isEmpty { issues.append(.missingBaseURL) }
        if trimmed(config.model).isEmpty { issues.append(.missingModel) }
        if trimmed(config.apiKey).isEmpty { issues.append(.missingAPIKey) }
        guard !trimmed(config.baseURL).isEmpty else { return issues }
        guard let components = URLComponents(string: trimmed(config.baseURL)),
              components.host?.isEmpty == false
        else {
            issues.append(.invalidBaseURL)
            return issues
        }
        guard let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme)
        else {
            issues.append(.unsupportedURLScheme)
            return issues
        }
        return issues
    }

    static func resolve(_ config: AIConfig) throws -> ResolvedAIProviderConfiguration {
        if let issue = validationIssues(for: config).first { throw issue }
        let manifest = manifest(for: config.provider)
        guard let endpointURL = endpointURL(baseURL: config.baseURL, manifest: manifest)
        else { throw AIConfigValidationIssue.invalidBaseURL }

        var effective = manifest.capabilities.resolving(
            model: config.model,
            preferences: config.preferences
        )
        if effective.webSearch.isEnabled,
           manifest.webSearch.requiresThinkingDisabled(for: config.model) {
            effective.displayableReasoning = .unavailable(.incompatibleCombination)
        }
        return ResolvedAIProviderConfiguration(
            manifest: manifest,
            endpointURL: endpointURL,
            baseURL: trimmed(config.baseURL),
            model: trimmed(config.model),
            apiKey: trimmed(config.apiKey),
            effectiveCapabilities: effective,
            profileID: config.profileID ?? AIModelCatalogScope.legacyProfileID,
            providerCapabilitySignals: config.providerCapabilitySignals ?? [:],
            providerMetadataObservedAt: config.providerMetadataObservedAt,
            webSearchRequested: config.preferences.webSearchEnabled,
            reasoningEffort: config.preferences.reasoningEffort
        )
    }

    private static func endpointURL(
        baseURL: String,
        manifest: AIProviderManifest
    ) -> URL? {
        guard var components = URLComponents(string: trimmed(baseURL)) else { return nil }
        components.query = nil
        components.fragment = nil
        let basePath = normalizedPath(components.path)
        let endpointPath = normalizedPath(manifest.endpointPath)
        if basePath == endpointPath || basePath.hasSuffix(endpointPath) {
            components.path = basePath
        } else if !basePath.isEmpty, endpointPath.hasPrefix(basePath + "/") {
            components.path = endpointPath
        } else {
            components.path = joinedPath(basePath, endpointPath)
        }
        return components.url
    }

    private static func capabilities(
        reasoning: CapabilitySupport,
        search: CapabilitySupport,
        image: CapabilitySupport,
        pdf: CapabilitySupport,
        directFile: CapabilitySupport,
        uploadedFile: CapabilitySupport,
        extraction: CapabilitySupport = .unsupported,
        fileSearch: CapabilitySupport = .unsupported
    ) -> ProviderCapabilities {
        ProviderCapabilities(
            streaming: .supported,
            functionTools: .supported,
            displayableReasoning: reasoning,
            webSearch: search,
            imageInput: image,
            inlinePDF: pdf,
            directFileInput: directFile,
            uploadedFileReference: uploadedFile,
            fileExtraction: extraction,
            fileSearch: fileSearch
        )
    }

    private static func support(
        _ capability: AIModelCapability,
        provider: AIProvider
    ) -> CapabilitySupport {
        AIProviderCapabilityRules.support(capability, provider: provider)
    }

    private static func data(for provider: AIProvider) -> AIManifestProvider {
        guard let value = AIModelManifestRepository.shared.provider(provider) else {
            preconditionFailure("Missing Manifest data for \(provider.rawValue)")
        }
        return value
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedPath(_ path: String) -> String {
        guard !path.isEmpty, path != "/" else { return "" }
        var value = path.hasPrefix("/") ? path : "/" + path
        while value.count > 1, value.hasSuffix("/") { value.removeLast() }
        return value
    }

    private static func joinedPath(_ base: String, _ suffix: String) -> String {
        normalizedPath(base) + normalizedPath(suffix)
    }
}
