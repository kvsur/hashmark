//
//  OpenAIResponsesStreamParser.swift
//  MarkdownApp
//
//  Responses 专属 SSE framing 与 typed event -> App-domain event 映射。
//

import Foundation

nonisolated final class OpenAIResponsesStreamParser {
    private var framer = SSEEventFramer()
    private var responseID: String?
    private var reasoningByItem: [String: String] = [:]
    private var emittedToolCallIDs: Set<String> = []
    private var emittedCitationIDs: Set<String> = []
    private var currentPhase: AIGenerationPhase?
    private var sawToolCall = false

    private(set) var completedResponseID: String?

    func receive(line: String) throws -> [AIStreamEvent] {
        try map(framer.receive(line: line))
    }

    func finish() throws -> [AIStreamEvent] {
        try map(framer.finish())
    }

    private func map(_ frames: [SSEFrame]) throws -> [AIStreamEvent] {
        try frames.flatMap { frame in
            switch frame {
            case .data(let data): return try map(OpenAIResponsesWireEvent(data: data))
            case .done: return []
            }
        }
    }

    private func map(_ event: OpenAIResponsesWireEvent) throws -> [AIStreamEvent] {
        switch event {
        case .created(let response):
            responseID = response.id
            return phase(.connecting)
        case .inProgress(let response):
            responseID = response.id
            return []
        case .outputTextDelta(let delta):
            return phase(.generating) + [.text(delta)]
        case .reasoningSummaryDelta(let itemID, let delta):
            reasoningByItem[itemID, default: ""] += delta
            return phase(.thinking) + [.reasoningDelta(delta)]
        case .reasoningSummaryDone(let itemID, let text):
            let visibleText = text ?? reasoningByItem.removeValue(forKey: itemID) ?? ""
            guard !visibleText.isEmpty else { return [] }
            return [.reasoningBlock(AIReasoningBlock(visibleText: visibleText))]
        case .functionArgumentsDone(let itemID, let callID, let name, let arguments):
            return toolCall(id: callID ?? itemID, name: name, arguments: arguments)
        case .outputItemAdded(let item):
            switch item.type {
            case "web_search_call", "file_search_call":
                return phase(.searching) + [.search(.started(AISearchActivity(
                    provider: .openAI,
                    query: nil,
                    requestID: item.id
                )))]
            case "function_call": return phase(.usingTool)
            default: return []
            }
        case .outputItemDone(let item):
            return outputItemEvents(item)
        case .webSearchActivity, .fileSearchActivity:
            return phase(.searching) + [.search(.started(AISearchActivity(
                provider: .openAI,
                query: nil,
                requestID: responseID
            )))]
        case .refusalDelta(let delta):
            return phase(.generating) + [.text(delta)]
        case .completed(let response):
            responseID = response.id
            completedResponseID = response.id
            var events = response.output?.flatMap(outputItemEvents) ?? []
            if let usage = response.usage { events.append(.usage(domainUsage(usage))) }
            events.append(.continuation(AIProviderContinuation(
                provider: .openAI,
                kind: "response_id",
                payload: .string(response.id)
            )))
            events.append(.stopReason(sawToolCall ? .toolUse : .endTurn))
            return events
        case .incomplete(let response):
            responseID = response.id
            completedResponseID = response.id
            var events: [AIStreamEvent] = []
            if let usage = response.usage { events.append(.usage(domainUsage(usage))) }
            events.append(.continuation(AIProviderContinuation(
                provider: .openAI,
                kind: "response_id",
                payload: .string(response.id)
            )))
            events.append(.stopReason(stopReason(response.incompleteDetails?.reason)))
            return events
        case .failed(let message):
            throw OpenAIResponsesWireError.remote(message)
        case .unknown:
            // Responses 会持续增加事件；未知事件可忽略，已建模终态仍必须到达。
            return []
        }
    }

    private func outputItemEvents(_ item: OpenAIResponsesWireOutputItem) -> [AIStreamEvent] {
        switch item.type {
        case "function_call":
            guard let name = item.name, let arguments = item.arguments else { return [] }
            return toolCall(id: item.callID ?? item.id ?? name, name: name, arguments: arguments)
        case "web_search_call":
            return phase(.searching) + [.search(.started(AISearchActivity(
                provider: .openAI,
                query: nil,
                requestID: item.id
            )))] + citations(item.action?.sources ?? [])
        case "file_search_call":
            return phase(.searching)
        case "message":
            let annotations = item.content?.flatMap { $0.annotations ?? [] } ?? []
            return annotationCitations(annotations)
        default:
            return []
        }
    }

    private func toolCall(id: String, name: String, arguments: String) -> [AIStreamEvent] {
        guard emittedToolCallIDs.insert(id).inserted else { return [] }
        sawToolCall = true
        return phase(.usingTool) + [.toolCall(AIToolCall(id: id, name: name, arguments: arguments))]
    }

    private func citations(_ sources: [OpenAIResponsesWireSource]) -> [AIStreamEvent] {
        sources.compactMap { source in
            guard let rawURL = source.url,
                  let url = AISearchSourceValidator.url(rawURL) else { return nil }
            return citation(
                title: source.title ?? url.host ?? rawURL,
                url: url,
                publisher: source.publisher,
                marker: nil
            )
        }
    }

    private func annotationCitations(
        _ annotations: [OpenAIResponsesWireAnnotation]
    ) -> [AIStreamEvent] {
        annotations.compactMap { annotation in
            guard annotation.type == "url_citation",
                  let rawURL = annotation.url,
                  let url = AISearchSourceValidator.url(rawURL)
            else { return nil }
            let marker: String?
            if let start = annotation.startIndex, let end = annotation.endIndex {
                marker = "\(start):\(end)"
            } else {
                marker = nil
            }
            return citation(
                title: annotation.title ?? url.host ?? rawURL,
                url: url,
                publisher: url.host,
                marker: marker
            )
        }
    }

    private func citation(
        title: String,
        url: URL,
        publisher: String?,
        marker: String?
    ) -> AIStreamEvent? {
        let id = "openai|\(url.absoluteString)"
        guard emittedCitationIDs.insert(id).inserted else { return nil }
        return .search(.citation(AISearchCitation(
            id: id,
            title: title,
            url: url,
            publisher: publisher,
            marker: marker,
            provider: .openAI,
            sourceIdentity: url.absoluteString
        )))
    }

    private func phase(_ next: AIGenerationPhase) -> [AIStreamEvent] {
        guard currentPhase != next else { return [] }
        currentPhase = next
        return [.phase(next)]
    }

    private func domainUsage(_ usage: OpenAIResponsesWireUsage) -> AIUsage {
        AIUsage(
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            totalTokens: usage.totalTokens
        )
    }

    private func stopReason(_ reason: String?) -> AIStreamStopReason {
        switch reason {
        case "max_output_tokens": .maxTokens
        case "content_filter": .refusal
        case .some(let value): .unknown(value)
        case nil: .unknown("incomplete")
        }
    }
}
