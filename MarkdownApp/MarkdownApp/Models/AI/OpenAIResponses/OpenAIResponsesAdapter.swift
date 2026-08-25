//
//  OpenAIResponsesAdapter.swift
//  MarkdownApp
//
//  OpenAI 只经 Responses API 接入；不含 Chat Completions 或兼容 fallback。
//

import Foundation

nonisolated final class OpenAIResponsesAdapter: AIProviderAdapter, @unchecked Sendable {
    let provider: AIProvider = .openAI
    let configuration: ResolvedAIProviderConfiguration

    private let session: URLSession
    private let conversationState = OpenAIResponsesSessionState()
    private let fileService: OpenAIResponsesFileService

    init(
        configuration: ResolvedAIProviderConfiguration,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
        self.fileService = OpenAIResponsesFileService(
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
                    let state = await conversationState.context(totalMessageCount: messages.count)
                    let incrementalMessages = requestMessages(
                        messages,
                        consumedCount: state.consumedMessageCount,
                        hasPreviousResponse: state.previousResponseID != nil
                    )
                    let instructions = messages
                        .filter { $0.role == .system }
                        .map(\.content)
                        .filter { !$0.isEmpty }
                        .joined(separator: "\n\n")
                    let request = try OpenAIResponsesRequestBuilder(configuration: configuration)
                        .makeStreamRequest(
                            messages: incrementalMessages,
                            instructions: instructions.isEmpty ? nil : instructions,
                            tools: tools,
                            previousResponseID: state.previousResponseID
                        )

                    AIDiagnostics.requestStarted(
                        provider: .openAI,
                        request: request,
                        model: configuration.model,
                        messageCount: incrementalMessages.count,
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
                        throw AIError.http(
                            status: http.statusCode,
                            body: try await responseBody(bytes)
                        )
                    }

                    let parser = OpenAIResponsesStreamParser()
                    var searchGate = AIWebSearchExecutionGate(
                        isRequired: webSearch
                    )
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        for event in try parser.receive(line: line) {
                            guard searchGate.accepts(event) else {
                                throw AIError.webSearchNotExecuted
                            }
                            AIDiagnostics.streamEvent(provider: .openAI, kind: diagnosticKind(event))
                            continuation.yield(event)
                        }
                    }
                    for event in try parser.finish() {
                        guard searchGate.accepts(event) else {
                            throw AIError.webSearchNotExecuted
                        }
                        AIDiagnostics.streamEvent(provider: .openAI, kind: diagnosticKind(event))
                        continuation.yield(event)
                    }
                    guard searchGate.isSatisfied else { throw AIError.webSearchNotExecuted }
                    if webSearch {
                        AICapabilityVerificationRecorder.recordNativeSearchSuccess(
                            configuration: configuration
                        )
                    }
                    guard let responseID = parser.completedResponseID else {
                        throw AIError.stream("missing_terminal_response")
                    }
                    await conversationState.complete(
                        responseID: responseID,
                        consumedMessageCount: messages.count
                    )
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
                } catch let error as OpenAIResponsesWireError {
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

    private func requestMessages(
        _ messages: [AIMessage],
        consumedCount: Int,
        hasPreviousResponse: Bool
    ) -> [AIMessage] {
        guard hasPreviousResponse else { return messages }
        // previous_response_id 已包含上一轮 assistant output；这里只发送新 user/tool input。
        return Array(messages.dropFirst(min(consumedCount, messages.count))).filter {
            $0.role != .assistant && $0.role != .system
        }
    }

    private func responseBody(_ bytes: URLSession.AsyncBytes) async throws -> String? {
        var data = Data()
        for try await byte in bytes {
            if data.count < 32_768 { data.append(byte) }
        }
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
