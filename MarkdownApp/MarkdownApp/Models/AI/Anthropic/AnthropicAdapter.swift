//
//  AnthropicAdapter.swift
//  MarkdownApp
//
//  Anthropic Messages Adapter；MiniMax 官方兼容主机仅扩展其独立搜索服务，
//  生成请求与流仍严格使用 Anthropic wire，不复用 OpenAI 类型。
//

import Foundation

nonisolated final class AnthropicAdapter: AIProviderAdapter, @unchecked Sendable {
    let provider: AIProvider = .anthropic
    let configuration: ResolvedAIProviderConfiguration

    private let session: URLSession
    private let fileService: AnthropicFileService
    private let miniMaxSearchService: MiniMaxWebSearchService

    init(configuration: ResolvedAIProviderConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
        self.fileService = AnthropicFileService(configuration: configuration, session: session)
        self.miniMaxSearchService = MiniMaxWebSearchService(
            configuration: configuration,
            session: session
        )
    }

    func stream(
        messages: [AIMessage],
        tools: [AITool]
    ) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let webSearch = configuration.usesNativeWebSearch
                do {
                    var requestMessages = messages
                    let usesMiniMaxSearch = webSearch
                        && MiniMaxWebSearchContract.matches(configuration)
                    if usesMiniMaxSearch {
                        guard let query = pendingWebSearchQuery(in: messages) else {
                            throw AIError.webSearchNotExecuted
                        }
                        let activity = AISearchActivity(
                            provider: .anthropic,
                            query: query,
                            requestID: nil
                        )
                        continuation.yield(.phase(.searching))
                        continuation.yield(.search(.started(activity)))
                        AIDiagnostics.streamEvent(provider: .anthropic, kind: "search")
                        let result = try await miniMaxSearchService.search(query: query)
                        for citation in result.citations {
                            continuation.yield(.search(.citation(citation)))
                        }
                        continuation.yield(.search(.completed(.anthropic)))
                        requestMessages = try MiniMaxWebSearchContract.appendingResult(
                            result,
                            query: query,
                            to: messages
                        )
                        let policy = await MainActor.run {
                            LocalizationController.string(
                                "The app has already completed Web Search for this turn. Use the attached web_search result as the source for current information, never claim that internet access is unavailable when it is present, do not request another web_search, and clearly say when the result lacks reliable evidence instead of answering from memory."
                            )
                        }
                        requestMessages.insert(
                            AIMessage(role: .system, content: policy),
                            at: 0
                        )
                    }
                    let request = try AnthropicRequestBuilder(configuration: configuration)
                        .makeStreamRequest(messages: requestMessages, tools: tools)
                    AIDiagnostics.requestStarted(
                        provider: .anthropic,
                        request: request,
                        model: configuration.model,
                        messageCount: requestMessages.count,
                        appToolCount: tools.count,
                        webSearchEnabled: webSearch
                    )
                    continuation.yield(.phase(.connecting))
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw AIError.stream("invalid_http_response")
                    }
                    AIDiagnostics.response(http, request: request)
                    guard (200..<300).contains(http.statusCode) else {
                        throw AIError.http(status: http.statusCode, body: try await responseBody(bytes))
                    }

                    let parser = AnthropicStreamParser { event in
                        Self.recordWireDiagnostic(event)
                    }
                    var searchGate = AIWebSearchExecutionGate(
                        isRequired: webSearch && !usesMiniMaxSearch
                    )
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        for event in try parser.receive(line: line) {
                            guard searchGate.accepts(event) else {
                                throw AIError.webSearchNotExecuted
                            }
                            AIDiagnostics.streamEvent(provider: .anthropic, kind: diagnosticKind(event))
                            continuation.yield(event)
                        }
                    }
                    for event in try parser.finish() {
                        guard searchGate.accepts(event) else {
                            throw AIError.webSearchNotExecuted
                        }
                        continuation.yield(event)
                    }
                    guard searchGate.isSatisfied else { throw AIError.webSearchNotExecuted }
                    if webSearch {
                        AICapabilityVerificationRecorder.recordNativeSearchSuccess(
                            configuration: configuration
                        )
                    }
                    await fileService.didCompleteResponse()
                    continuation.finish()
                } catch is CancellationError {
                    AICapabilityVerificationRecorder.recordNativeSearchFailure(
                        CancellationError(), configuration: configuration
                    )
                    continuation.finish(throwing: CancellationError())
                } catch let error as AIError {
                    AICapabilityVerificationRecorder.recordNativeSearchFailure(
                        error, configuration: configuration
                    )
                    continuation.finish(throwing: error)
                } catch let error as AnthropicWireError {
                    let wrapped = AIError.stream(String(describing: error))
                    AICapabilityVerificationRecorder.recordNativeSearchFailure(
                        wrapped, configuration: configuration
                    )
                    continuation.finish(throwing: wrapped)
                } catch {
                    let wrapped = AIError.network(error)
                    AICapabilityVerificationRecorder.recordNativeSearchFailure(
                        wrapped, configuration: configuration
                    )
                    continuation.finish(throwing: wrapped)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    func upload(_ request: AIFileUploadRequest) async throws -> AIProviderFileReference {
        try await fileService.upload(request)
    }

    func delete(_ reference: AIProviderFileReference) async throws {
        try await fileService.delete(reference)
    }

    private func responseBody(_ bytes: URLSession.AsyncBytes) async throws -> String? {
        var data = Data()
        for try await byte in bytes where data.count < 32_768 { data.append(byte) }
        return String(data: data, encoding: .utf8)
    }

    private func pendingWebSearchQuery(in messages: [AIMessage]) -> String? {
        guard let message = messages.last(where: { $0.role == .user }) else { return nil }
        let query = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? nil : query
    }

    private func diagnosticKind(_ event: AIStreamEvent) -> String {
        switch event {
        case .phase: "phase"
        case .reasoningDelta: "reasoning_delta"
        case .reasoningBlock: "reasoning_block"
        case .text: "text_delta"
        case .toolCall: "function_call"
        case .search: "search"
        case .fileState: "file_state"
        case .usage: "usage"
        case .continuation: "continuation"
        case .stopReason: "stop_reason"
        }
    }

    private static func recordWireDiagnostic(_ event: AnthropicWireEvent) {
        switch event {
        case .messageStart:
            AIDiagnostics.anthropicWireEvent(kind: "message_start")
        case .blockStart(_, let block):
            AIDiagnostics.anthropicWireEvent(
                kind: "content_block_start",
                blockType: block.type,
                toolName: block.name
            )
        case .blockStop:
            AIDiagnostics.anthropicWireEvent(kind: "content_block_stop")
        case .messageDelta(let reason, _):
            AIDiagnostics.anthropicWireEvent(
                kind: "message_delta",
                stopReason: reason
            )
        case .messageStop:
            AIDiagnostics.anthropicWireEvent(kind: "message_stop")
        case .ping, .textDelta, .thinkingDelta, .signatureDelta,
             .inputJSONDelta, .citationDelta:
            break
        }
    }
}
