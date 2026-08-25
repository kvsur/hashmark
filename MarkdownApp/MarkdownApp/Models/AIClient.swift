//
//  AIClient.swift
//  MarkdownApp
//
//  会话使用的中立流接口、工厂、动态上下文、隐私诊断和错误语义。
//  传输、鉴权、serializer/parser 与 native tool/file lifecycle 均由 Provider Adapter 私有实现。
//

import Foundation
#if DEBUG
import OSLog
#endif

nonisolated protocol AIClient {
    func stream(messages: [AIMessage], tools: [AITool]) -> AsyncThrowingStream<AIStreamEvent, Error>
}

nonisolated enum AIClientFactory {
    static func make(_ config: AIConfig) throws -> AIClient {
        let resolved: ResolvedAIProviderConfiguration
        do {
            resolved = try AIProviderRegistry.resolve(config)
        } catch {
            throw AIError.invalidURL
        }
        guard !config.preferences.webSearchEnabled
                || resolved.usesNativeWebSearch
        else {
            throw AIError.webSearchUnavailable
        }
        return try AIProviderAdapterFactory.make(resolved)
    }
}

nonisolated enum AIDiagnostics {
#if DEBUG
    private static let logger = Logger(subsystem: "com.kvsur.MarkdownApp", category: "AI.API")
#endif

    static func requestStarted(
        provider: AIProvider,
        request: URLRequest,
        model: String,
        messageCount: Int,
        appToolCount: Int,
        webSearchEnabled: Bool
    ) {
#if DEBUG
        logger.notice(
            "[AI-Debug] request-start provider=\(provider.rawValue, privacy: .public) host=\(request.url?.host ?? "unknown", privacy: .public) path=\(request.url?.path ?? "unknown", privacy: .public) model=\(model, privacy: .public) messages=\(messageCount) appTools=\(appToolCount) webSearch=\(webSearchEnabled) bodyBytes=\(request.httpBody?.count ?? 0)"
        )
#endif
    }

    static func response(_ response: HTTPURLResponse, request: URLRequest) {
#if DEBUG
        logger.notice(
            "[AI-Debug] response host=\(request.url?.host ?? "unknown", privacy: .public) path=\(request.url?.path ?? "unknown", privacy: .public) status=\(response.statusCode)"
        )
#endif
    }

    static func streamEvent(provider: AIProvider, kind: String) {
#if DEBUG
        logger.debug(
            "[AI-Debug] stream-event provider=\(provider.rawValue, privacy: .public) kind=\(kind, privacy: .public)"
        )
#endif
    }

    static func streamDecodeFailure(provider: AIProvider, kind: String, path: String) {
#if DEBUG
        // 仅记录结构位置与错误类别，不记录原始 SSE、正文或工具参数。
        logger.error(
            "[AI-Debug] stream-decode-failed provider=\(provider.rawValue, privacy: .public) kind=\(kind, privacy: .public) path=\(path, privacy: .public)"
        )
#endif
    }

    static func attachmentPreflight(
        provider: AIProvider,
        attachmentCount: Int,
        totalBytes: Int,
        intents: [String]
    ) {
#if DEBUG
        logger.notice(
            "[AI-Debug] attachment-preflight provider=\(provider.rawValue, privacy: .public) count=\(attachmentCount) totalBytes=\(totalBytes) intents=\(intents.joined(separator: ","), privacy: .public)"
        )
#endif
    }

    static func sessionToolCall(
        name: String,
        argumentBytes: Int,
        phase: String,
        reasoningCharacters: Int,
        textCharacters: Int
    ) {
#if DEBUG
        logger.notice(
            "[AI-Debug] session-tool-call tool=\(name, privacy: .public) argumentBytes=\(argumentBytes) phase=\(phase, privacy: .public) reasoningChars=\(reasoningCharacters) textChars=\(textCharacters)"
        )
#endif
    }

    static func automaticWebSearchContinuation(name: String, turn: Int) {
#if DEBUG
        logger.notice(
            "[AI-Debug] native-search-continuation tool=\(name, privacy: .public) turn=\(turn)"
        )
#endif
    }

    static func automaticWebSearchGate(
        provider: String,
        model: String,
        adapter: String,
        mechanism: String,
        observedToolName: String,
        expectedToolName: String,
        decision: String,
        reason: String
    ) {
#if DEBUG
        logger.debug(
            "[AI-Debug] native-search-gate provider=\(provider, privacy: .public) model=\(model, privacy: .public) adapter=\(adapter, privacy: .public) mechanism=\(mechanism, privacy: .public) observedTool=\(observedToolName, privacy: .public) expectedTool=\(expectedToolName, privacy: .public) decision=\(decision, privacy: .public) reason=\(reason, privacy: .public)"
        )
#endif
    }

    static func unrecognizedTool(name: String, reason: String) {
#if DEBUG
        logger.error(
            "[AI-Debug] unrecognized-tool tool=\(name, privacy: .public) reason=\(reason, privacy: .public)"
        )
#endif
    }
}

enum AIError: LocalizedError {
    case notConfigured
    case invalidURL
    case providerUnavailable
    case webSearchUnavailable
    case webSearchNotExecuted
    case http(status: Int, body: String?)
    case network(Error)
    case stream(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            LocalizationController.string("AI is not configured yet. Fill it in under Settings first.")
        case .invalidURL:
            LocalizationController.string("The base URL is invalid. Check your AI configuration.")
        case .providerUnavailable:
            LocalizationController.string("Not available for this provider")
        case .webSearchUnavailable:
            LocalizationController.string(
                "Web Search is not available for this provider and model. Choose a supported model or turn it off in Settings."
            )
        case .webSearchNotExecuted:
            LocalizationController.string(
                "Web Search was required but the provider did not run it. Try again or check the provider configuration."
            )
        case .http(let status, let body):
            switch status {
            case 401, 403:
                LocalizationController.string("Authentication failed (\(status)). Check your API key.")
            case 429:
                LocalizationController.string("Too many requests (429). Try again shortly.")
            default:
                if let body {
                    LocalizationController.string("The service returned an error (\(status)): \(Self.truncated(body))")
                } else {
                    LocalizationController.string("The service returned an error (\(status)).")
                }
            }
        case .network(let error):
            LocalizationController.string("Network error: \(error.localizedDescription)")
        case .stream(let message):
            LocalizationController.string("The AI stream ended with an error: \(message)")
        }
    }

    private static func truncated(_ text: String, limit: Int = 300) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count <= limit ? trimmed : String(trimmed.prefix(limit)) + "..."
    }
}
