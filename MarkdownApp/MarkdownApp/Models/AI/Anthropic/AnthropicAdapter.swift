//
//  AnthropicAdapter.swift
//  MarkdownApp
//
//  Anthropic 仅通过官方 Messages API；不复用 OpenAI request/stream 类型。
//

import Foundation

nonisolated final class AnthropicAdapter: AIProviderAdapter, @unchecked Sendable {
    let provider: AIProvider = .anthropic
    let configuration: ResolvedAIProviderConfiguration

    private let session: URLSession
    private let fileService: AnthropicFileService

    init(configuration: ResolvedAIProviderConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
        self.fileService = AnthropicFileService(configuration: configuration, session: session)
    }

    func stream(
        messages: [AIMessage],
        tools: [AITool]
    ) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let webSearch = configuration.usesNativeWebSearch
                do {
                    let request = try AnthropicRequestBuilder(configuration: configuration)
                        .makeStreamRequest(messages: messages, tools: tools)
                    AIDiagnostics.requestStarted(
                        provider: .anthropic,
                        request: request,
                        model: configuration.model,
                        messageCount: messages.count,
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

                    let parser = AnthropicStreamParser()
                    var searchGate = AIWebSearchExecutionGate(
                        isRequired: webSearch
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
