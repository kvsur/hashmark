//
//  GLMStreamParser.swift
//  MarkdownApp
//
//  BigModel delta、reasoning、function 与顶层 web_search 来源映射。
//

import Foundation

nonisolated final class GLMStreamParser {
    private struct ToolState {
        var id = ""
        var name = ""
        var arguments = ""
    }

    private var framer = SSEEventFramer()
    private var tools: [Int: ToolState] = [:]
    private var reasoningContent = ""
    private var emittedCitationIDs: Set<String> = []
    private var currentPhase: AIGenerationPhase?
    private var lastUsage: GLMWireUsage?
    private var requestIdentity: String?
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
            case .data(let data): return map(try GLMWireChunk(data: data))
            case .done: return terminalEvents(reason: nil)
            }
        }
    }

    private func map(_ chunk: GLMWireChunk) -> [AIStreamEvent] {
        if let id = chunk.requestID ?? chunk.id { requestIdentity = id }
        if let usage = chunk.usage { lastUsage = usage }
        var events = citations(chunk.webSearch ?? [])
        guard let choice = chunk.choices?.first else { return events }
        if let reasoning = choice.delta?.reasoningContent, !reasoning.isEmpty {
            reasoningContent += reasoning
            events += phase(.thinking) + [.reasoningDelta(reasoning)]
        }
        if let text = choice.delta?.content, !text.isEmpty {
            events += phase(.generating) + [.text(text)]
        }
        for call in choice.delta?.toolCalls ?? [] where call.type != "web_search" {
            let index = call.index ?? 0
            var item = tools[index] ?? ToolState()
            if let id = call.id { item.id = id }
            if let name = call.function?.name { item.name = name }
            if let arguments = call.function?.arguments { item.arguments += arguments }
            tools[index] = item
        }
        if let reason = choice.finishReason { events += terminalEvents(reason: reason) }
        return events
    }

    private func terminalEvents(reason: String?) -> [AIStreamEvent] {
        guard !terminalEmitted else { return [] }
        terminalEmitted = true
        var events: [AIStreamEvent] = []
        if !reasoningContent.isEmpty {
            let continuation = AIProviderContinuation(
                provider: .glm,
                kind: "reasoning_content",
                payload: .string(reasoningContent)
            )
            events.append(.reasoningBlock(AIReasoningBlock(
                visibleText: reasoningContent,
                continuation: continuation
            )))
        }
        let completedTools = tools.keys.sorted().compactMap { index -> AIToolCall? in
            guard let tool = tools[index], !tool.name.isEmpty else { return nil }
            return AIToolCall(
                id: tool.id.isEmpty ? "call_\(index)" : tool.id,
                name: tool.name,
                arguments: tool.arguments.isEmpty ? "{}" : tool.arguments
            )
        }
        if !completedTools.isEmpty {
            events += phase(.usingTool)
            events += completedTools.map(AIStreamEvent.toolCall)
        }
        if let usage = lastUsage {
            events.append(.usage(AIUsage(
                inputTokens: usage.promptTokens,
                outputTokens: usage.completionTokens,
                totalTokens: usage.totalTokens
            )))
        }
        if let requestIdentity {
            events.append(.continuation(AIProviderContinuation(
                provider: .glm,
                kind: "request_id",
                payload: .string(requestIdentity)
            )))
        }
        events.append(.stopReason(stopReason(reason, hasTools: !completedTools.isEmpty)))
        return events
    }

    private func citations(_ sources: [GLMWireSearchResult]) -> [AIStreamEvent] {
        let values = sources.compactMap { source -> AIStreamEvent? in
            guard let rawURL = source.link,
                  let url = AISearchSourceValidator.url(rawURL) else { return nil }
            let id = "glm|\(url.absoluteString)"
            guard emittedCitationIDs.insert(id).inserted else { return nil }
            return .search(.citation(AISearchCitation(
                id: id,
                title: source.title ?? url.host ?? rawURL,
                url: url,
                publisher: source.media ?? url.host,
                marker: source.refer,
                provider: .glm,
                sourceIdentity: url.absoluteString
            )))
        }
        return values.isEmpty ? [] : phase(.searching) + [
            .search(.started(AISearchActivity(provider: .glm, query: nil, requestID: requestIdentity)))
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
        case "sensitive": return .refusal
        case .some(let value): return .unknown(value)
        }
    }
}
