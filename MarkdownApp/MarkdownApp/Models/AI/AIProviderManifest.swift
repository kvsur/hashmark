//
//  AIProviderManifest.swift
//  MarkdownApp
//
//  六家第一方 endpoint、鉴权、当前模型和原生工具机制的唯一事实源。
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
    case qwenDashScope
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

    var documentedModelIDs: [String] { capabilities.documentedModelIDs }
}

nonisolated struct ResolvedAIProviderConfiguration: Equatable {
    let manifest: AIProviderManifest
    let endpointURL: URL
    let model: String
    let apiKey: String
    let effectiveCapabilities: EffectiveProviderCapabilities

    var provider: AIProvider { manifest.provider }
}

nonisolated enum AIConfigValidationIssue: Error, Equatable {
    case missingBaseURL
    case missingModel
    case missingAPIKey
    case invalidBaseURL
    case unsupportedURLScheme
}

nonisolated enum AIProviderRegistry {
    static let manifests: [AIProvider: AIProviderManifest] = [
        .openAI: AIProviderManifest(
            provider: .openAI,
            verifiedAt: "2026-08-24",
            defaultBaseURL: "https://api.openai.com/v1",
            defaultModel: "gpt-5.6-terra",
            endpointPath: "/v1/responses",
            authentication: .bearer,
            webSearch: .openAIHostedTool(type: "web_search"),
            fileMechanisms: [.directInput, .uploadReference, .hostedRetrieval],
            capabilities: capabilities(
                reasoning: .conditional(AIProviderCapabilityRules.openAI),
                search: .conditional(AIProviderCapabilityRules.openAI),
                image: .conditional(AIProviderCapabilityRules.openAI),
                pdf: .conditional(AIProviderCapabilityRules.openAI),
                directFile: .conditional(AIProviderCapabilityRules.openAI),
                uploadedFile: .conditional(AIProviderCapabilityRules.openAI),
                fileSearch: .conditional(AIProviderCapabilityRules.openAI)
            )
        ),
        .anthropic: AIProviderManifest(
            provider: .anthropic,
            verifiedAt: "2026-08-24",
            defaultBaseURL: "https://api.anthropic.com",
            defaultModel: "claude-fable-5",
            endpointPath: "/v1/messages",
            authentication: .anthropic(apiVersion: "2023-06-01"),
            webSearch: .anthropicServerTool(version: "web_search_20260318"),
            fileMechanisms: [.directInput, .uploadReference],
            capabilities: capabilities(
                reasoning: .conditional(AIProviderCapabilityRules.anthropicReasoning),
                search: .conditional(AIProviderCapabilityRules.anthropicForcedSearch),
                image: .conditional(AIProviderCapabilityRules.anthropicInput),
                pdf: .conditional(AIProviderCapabilityRules.anthropicInput),
                directFile: .conditional(AIProviderCapabilityRules.anthropicInput),
                uploadedFile: .conditional(AIProviderCapabilityRules.anthropicInput)
            )
        ),
        .gemini: AIProviderManifest(
            provider: .gemini,
            verifiedAt: "2026-08-25",
            defaultBaseURL: "https://generativelanguage.googleapis.com",
            defaultModel: "gemini-3.7-flash",
            endpointPath: "/v1beta/interactions",
            authentication: .googleAPIKey,
            webSearch: .geminiGoogleSearch,
            fileMechanisms: [.directInput, .uploadReference, .hostedRetrieval],
            capabilities: capabilities(
                reasoning: .conditional(AIProviderCapabilityRules.geminiReasoning),
                search: .conditional(AIProviderCapabilityRules.geminiSearch),
                image: .conditional(AIProviderCapabilityRules.geminiMultimodal),
                pdf: .conditional(AIProviderCapabilityRules.geminiMultimodal),
                directFile: .conditional(AIProviderCapabilityRules.geminiMultimodal),
                uploadedFile: .conditional(AIProviderCapabilityRules.geminiMultimodal),
                fileSearch: .conditional(AIProviderCapabilityRules.geminiFileSearch)
            )
        ),
        .qwen: AIProviderManifest(
            provider: .qwen,
            verifiedAt: "2026-08-25",
            defaultBaseURL: "https://dashscope.aliyuncs.com/api/v1",
            defaultModel: "qwen3.7-plus",
            endpointPath: "/api/v1/services/aigc/text-generation/generation",
            authentication: .bearer,
            webSearch: .qwenDashScope,
            fileMechanisms: [.directInput, .uploadReference, .extraction, .hostedRetrieval],
            capabilities: capabilities(
                reasoning: .conditional(AIProviderCapabilityRules.qwenReasoning),
                search: .conditional(AIProviderCapabilityRules.qwenSearch),
                image: .conditional(AIProviderCapabilityRules.qwenMultimodal),
                pdf: .conditional(AIProviderCapabilityRules.qwenDocument),
                directFile: .conditional(AIProviderCapabilityRules.qwenDocument),
                uploadedFile: .conditional(AIProviderCapabilityRules.qwenDocument),
                extraction: .conditional(AIProviderCapabilityRules.qwenReasoning)
            )
        ),
        .kimi: AIProviderManifest(
            provider: .kimi,
            verifiedAt: "2026-08-25",
            defaultBaseURL: "https://api.moonshot.cn/v1",
            defaultModel: "kimi-k2.6",
            endpointPath: "/v1/chat/completions",
            authentication: .bearer,
            webSearch: .kimiFormula(
                name: "web_search",
                uri: "moonshot/web-search:latest",
                requiresThinkingDisabled: true
            ),
            fileMechanisms: [.directInput, .uploadReference, .extraction],
            capabilities: capabilities(
                reasoning: .conditional(AIProviderCapabilityRules.kimiReasoning),
                // Formula 是 Provider 级工具；具体模型清单不应把用户已开启的搜索静默移除。
                search: .supported,
                image: .conditional(AIProviderCapabilityRules.kimiVisual),
                // Files/file-extract 先解析为文本，再交给聊天模型，属于 Provider 级能力。
                pdf: .supported,
                directFile: .supported,
                uploadedFile: .supported,
                extraction: .supported
            )
        ),
        .glm: AIProviderManifest(
            provider: .glm,
            verifiedAt: "2026-08-25",
            defaultBaseURL: "https://open.bigmodel.cn",
            defaultModel: "glm-5.3",
            endpointPath: "/api/paas/v4/chat/completions",
            authentication: .bearer,
            webSearch: .glmStandaloneAPI,
            fileMechanisms: [.directInput, .uploadReference],
            capabilities: capabilities(
                reasoning: .conditional(AIProviderCapabilityRules.glmReasoning),
                search: .conditional(AIProviderCapabilityRules.glmText),
                image: .conditional(AIProviderCapabilityRules.glmVision),
                pdf: .conditional(AIProviderCapabilityRules.glmVision),
                directFile: .conditional(AIProviderCapabilityRules.glmVision),
                uploadedFile: .conditional(AIProviderCapabilityRules.glmVision)
            )
        )
    ]

    static func manifest(for provider: AIProvider) -> AIProviderManifest {
        manifests[provider]!
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
            model: trimmed(config.model),
            apiKey: trimmed(config.apiKey),
            effectiveCapabilities: effective
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
