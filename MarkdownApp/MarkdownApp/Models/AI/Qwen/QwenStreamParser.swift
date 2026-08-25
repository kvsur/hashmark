//
//  QwenStreamParser.swift
//  MarkdownApp
//
//  DashScope result SSE、reasoning/tool/search_info 与终态映射。
//

import Foundation

nonisolated final class QwenStreamParser {
    private struct ToolState {
        var id = ""
        var name = ""
        var arguments = ""
    }

    private var framer = SSEEventFramer()
    private var tools: [Int: ToolState] = [:]
    private var emittedCitationIDs: Set<String> = []
    private var currentPhase: AIGenerationPhase?
    private var lastUsage: QwenWireUsage?
    private var requestID: String?
    private var terminalEmitted = false

    func receive(line: String) throws -> [AIStreamEvent] {
        try map(framer.receive(line: line))
    }

    func finish() throws -> [AIStreamEvent] {
        var events = try map(framer.finish())
        if !terminalEmitted { events += terminalEvents(reason: nil) }
        return events
    }

    private func map(_ frames: [SSEFrame]) throws -> [AIStreamEvent] {
        try frames.flatMap { frame in
            switch frame {
            case .data(let data): return map(try QwenWireChunk(data: data))
            case .done: return terminalEvents(reason: nil)
            }
        }
    }

    private func map(_ chunk: QwenWireChunk) -> [AIStreamEvent] {
        if let usage = chunk.usage { lastUsage = usage }
        if let id = chunk.requestID { requestID = id }
        var events = citations(chunk.output?.searchInfo?.searchResults ?? [])
        guard let choice = chunk.output?.choices?.first else { return events }
        if let reasoning = choice.message?.reasoningContent, !reasoning.isEmpty {
            events += phase(.thinking) + [.reasoningDelta(reasoning)]
        }
        if let content = choice.message?.content {
            let text = textContent(content)
            if !text.isEmpty { events += phase(.generating) + [.text(text)] }
        }
        for call in choice.message?.toolCalls ?? [] {
            let index = call.index ?? 0
            var item = tools[index] ?? ToolState()
            if let id = call.id { item.id = id }
            if let name = call.function?.name { item.name = name }
            if let arguments = call.function?.arguments { item.arguments += arguments }
            tools[index] = item
        }
        let reason = choice.finishReason
        if reason != nil, reason != "null" { events += terminalEvents(reason: reason) }
        return events
    }

    private func terminalEvents(reason: String?) -> [AIStreamEvent] {
        guard !terminalEmitted else { return [] }
        terminalEmitted = true
        var events: [AIStreamEvent] = tools.keys.sorted().compactMap { index in
            guard let tool = tools[index], !tool.name.isEmpty else { return nil }
            return .toolCall(AIToolCall(
                id: tool.id.isEmpty ? "call_\(index)" : tool.id,
                name: tool.name,
                arguments: tool.arguments.isEmpty ? "{}" : tool.arguments
            ))
        }
        if !tools.isEmpty { events = phase(.usingTool) + events }
        if let usage = lastUsage {
            events.append(.usage(AIUsage(
                inputTokens: usage.inputTokens,
                outputTokens: usage.outputTokens,
                totalTokens: usage.totalTokens
            )))
        }
        if let requestID {
            events.append(.continuation(AIProviderContinuation(
                provider: .qwen,
                kind: "request_id",
                payload: .string(requestID)
            )))
        }
        events.append(.stopReason(stopReason(reason, hasTools: !tools.isEmpty)))
        return events
    }

    private func textContent(_ value: JSONValue) -> String {
        switch value {
        case .string(let text): text
        case .array(let values): values.compactMap { value in
            guard case .object(let object) = value,
                  case .string(let text)? = object["text"] else { return nil }
            return text
        }.joined()
        default: ""
        }
    }

    private func citations(_ sources: [QwenWireSearchResult]) -> [AIStreamEvent] {
        let values = sources.compactMap { source -> AIStreamEvent? in
            guard let rawURL = source.url,
                  let url = AISearchSourceValidator.url(rawURL) else { return nil }
            let id = "qwen|\(url.absoluteString)"
            guard emittedCitationIDs.insert(id).inserted else { return nil }
            return .search(.citation(AISearchCitation(
                id: id,
                title: source.title ?? url.host ?? rawURL,
                url: url,
                publisher: source.siteName ?? url.host,
                marker: source.index.map(String.init),
                provider: .qwen,
                sourceIdentity: url.absoluteString
            )))
        }
        return values.isEmpty ? [] : phase(.searching) + [
            .search(.started(AISearchActivity(provider: .qwen, query: nil, requestID: requestID)))
        ] + values
    }

    private func phase(_ next: AIGenerationPhase) -> [AIStreamEvent] {
        guard currentPhase != next else { return [] }
        currentPhase = next
        return [.phase(next)]
    }

    private func stopReason(_ value: String?, hasTools: Bool) -> AIStreamStopReason {
        if hasTools { return .toolUse }
        switch value {
        case "stop", nil: return .endTurn
        case "length": return .maxTokens
        case "tool_calls": return .toolUse
        case "content_filter": return .refusal
        case .some(let value): return .unknown(value)
        }
    }
}
