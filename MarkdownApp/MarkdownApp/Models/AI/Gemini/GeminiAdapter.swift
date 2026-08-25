//
//  GeminiAdapter.swift
//  MarkdownApp
//
//  Gemini 仅通过 Interactions + first-party Files；不调用 OpenAI compatibility route。
//

import Foundation

nonisolated final class GeminiAdapter: AIProviderAdapter, @unchecked Sendable {
    let provider: AIProvider = .gemini
    let configuration: ResolvedAIProviderConfiguration

    private let session: URLSession
    private let conversationState = GeminiInteractionState()
    private let fileService: GeminiFileService

    init(configuration: ResolvedAIProviderConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
        self.fileService = GeminiFileService(configuration: configuration, session: session)
    }

    func stream(
        messages: [AIMessage],
        tools: [AITool]
    ) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let state = await conversationState.context(totalMessageCount: messages.count)
                    let incremental = requestMessages(
                        messages,
                        consumedCount: state.consumedMessageCount,
                        hasPreviousInteraction: state.previousInteractionID != nil
                    )
                    let request = try GeminiRequestBuilder(configuration: configuration).makeStreamRequest(
                        messages: incremental,
                        tools: tools,
                        previousInteractionID: state.previousInteractionID
                    )
                    AIDiagnostics.requestStarted(
                        provider: .gemini,
                        request: request,
                        model: configuration.model,
                        messageCount: incremental.count,
                        appToolCount: tools.count,
                        webSearchEnabled: configuration.effectiveCapabilities.webSearch.isEnabled
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

                    let parser = GeminiStreamParser()
                    var searchGate = AIWebSearchExecutionGate(
                        isRequired: configuration.effectiveCapabilities.webSearch.isEnabled
                    )
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        for event in try parser.receive(line: line) {
                            guard searchGate.accepts(event) else {
                                throw AIError.webSearchNotExecuted
                            }
                            AIDiagnostics.streamEvent(provider: .gemini, kind: diagnosticKind(event))
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
                    guard let interactionID = parser.completedInteractionID else {
                        throw GeminiWireError.missingTerminalInteraction
                    }
                    await conversationState.complete(
                        interactionID: interactionID,
                        consumedMessageCount: messages.count
                    )
                    await fileService.didCompleteResponse()
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch let error as AIError {
                    continuation.finish(throwing: error)
                } catch let error as GeminiWireError {
                    continuation.finish(throwing: AIError.stream(String(describing: error)))
                } catch {
                    continuation.finish(throwing: AIError.network(error))
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

    private func requestMessages(
        _ messages: [AIMessage],
        consumedCount: Int,
        hasPreviousInteraction: Bool
    ) -> [AIMessage] {
        guard hasPreviousInteraction else { return messages }
        let newMessages = Array(messages.dropFirst(min(consumedCount, messages.count)))
        let system = messages.filter { $0.role == .system }
        return system + newMessages.filter { $0.role != .system && $0.role != .assistant }
    }

    private func responseBody(_ bytes: URLSession.AsyncBytes) async throws -> String? {
        var data = Data()
        for try await byte in bytes where data.count < 32_768 { data.append(byte) }
        return String(data: data, encoding: .utf8)
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
}
