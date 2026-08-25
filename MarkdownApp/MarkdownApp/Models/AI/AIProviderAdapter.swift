//
//  AIProviderAdapter.swift
//  MarkdownApp
//
//  粗粒度 App-domain Adapter。每家 Provider 在自己的目录实现请求、流、工具与文件协议；
//  此处不定义共享 wire body、SSE parser 或兼容协议。
//

import Foundation

nonisolated protocol AIProviderAdapter: AIClient {
    var provider: AIProvider { get }
    var configuration: ResolvedAIProviderConfiguration { get }

    func upload(_ request: AIFileUploadRequest) async throws -> AIProviderFileReference
    func delete(_ reference: AIProviderFileReference) async throws
    func resolveNativeSearch(_ continuation: AISearchContinuation) async throws -> String
}

nonisolated extension AIProviderAdapter {
    func upload(_ request: AIFileUploadRequest) async throws -> AIProviderFileReference {
        throw AIError.providerUnavailable
    }

    func delete(_ reference: AIProviderFileReference) async throws {
        throw AIError.providerUnavailable
    }

    func resolveNativeSearch(_ continuation: AISearchContinuation) async throws -> String {
        throw AIError.providerUnavailable
    }
}

nonisolated enum AIProviderAdapterFactory {
    static func make(_ configuration: ResolvedAIProviderConfiguration) throws -> AIProviderAdapter {
        // 保持 exhaustive switch：新增 Provider 时编译器会强制补充，不能落入兼容 fallback。
        switch configuration.provider {
        case .openAI:
            return OpenAIResponsesAdapter(configuration: configuration)
        case .anthropic:
            return AnthropicAdapter(configuration: configuration)
        case .gemini:
            return GeminiAdapter(configuration: configuration)
        case .qwen:
            return QwenAdapter(configuration: configuration)
        case .kimi:
            return KimiAdapter(configuration: configuration)
        case .glm:
            return GLMAdapter(configuration: configuration)
        }
    }
}
