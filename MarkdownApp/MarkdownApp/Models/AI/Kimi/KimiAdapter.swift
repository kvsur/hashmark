//
//  KimiAdapter.swift
//  MarkdownApp
//
//  Kimi 第一方 chat/files Adapter；请求、流和工具生命周期均为 Provider 私有。
//

import Foundation

nonisolated final class KimiAdapter: AIProviderAdapter, @unchecked Sendable {
    let provider: AIProvider = .kimi
    let configuration: ResolvedAIProviderConfiguration

    private let session: URLSession
    private let fileService: KimiFileService
    private let formulaService: KimiFormulaService

    init(configuration: ResolvedAIProviderConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
        self.fileService = KimiFileService(configuration: configuration, session: session)
        self.formulaService = KimiFormulaService(configuration: configuration, session: session)
    }

    func stream(
        messages: [AIMessage],
        tools: [AITool]
    ) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let requestBuilder = KimiRequestBuilder(configuration: configuration)
                    let webSearch = configuration.effectiveCapabilities.webSearch.isEnabled
                    let formulaTools: [JSONValue]
                    if webSearch {
                        formulaTools = [try await formulaService.webSearchTool()]
                    } else {
                        formulaTools = []
                    }
                    var requestMessages = messages
                    if webSearch {
                        guard let query = requestBuilder.pendingWebSearchQuery(in: messages) else {
                            throw AIError.webSearchNotExecuted
                        }
                        let arguments = try KimiFormulaContract.webSearchArguments(query: query)
                        let activity = AISearchActivity(
                            provider: .kimi,
                            query: query,
                            requestID: nil
                        )
                        continuation.yield(.phase(.searching))
                        continuation.yield(.search(.started(activity)))
                        AIDiagnostics.streamEvent(provider: .kimi, kind: "search")
                        let result = try await formulaService.executeWebSearch(arguments: arguments)
                        requestMessages = KimiFormulaContract.appendingWebSearchResult(
                            to: messages,
                            callID: "web_search:\(UUID().uuidString)",
                            arguments: arguments,
                            result: result
                        )
                        continuation.yield(.search(.completed(.kimi)))
                    }
                    let webSearchPolicy = webSearch
                        ? await MainActor.run {
                            LocalizationController.string(
                                "The app has already completed Web Search for this turn. Use the attached web_search result as the source for current information, never claim that internet access is unavailable when it is present, do not request another web_search, and clearly say when the result lacks reliable evidence instead of answering from memory."
                            )
                        }
                        : nil
                    let request = try requestBuilder.makeStreamRequest(
                        messages: requestMessages,
                        tools: tools,
                        formulaTools: formulaTools,
                        webSearchPolicy: webSearchPolicy
                    )
                    AIDiagnostics.requestStarted(
                        provider: .kimi,
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

                    let parser = KimiStreamParser()
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        for event in try parser.receive(line: line) {
                            AIDiagnostics.streamEvent(provider: .kimi, kind: diagnosticKind(event))
                            continuation.yield(event)
                        }
                    }
                    for event in try parser.finish() { continuation.yield(event) }
                    await fileService.didCompleteResponse()
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch let error as AIError {
                    continuation.finish(throwing: error)
                } catch let error as KimiWireError {
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
