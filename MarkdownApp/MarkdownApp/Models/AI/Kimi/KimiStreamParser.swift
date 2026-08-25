//
//  KimiStreamParser.swift
//  MarkdownApp
//
//  Kimi delta/reasoning_content/builtin tool stream 与来源映射。
//

import Foundation

nonisolated final class KimiStreamParser {
    private struct ToolState {
        var id = ""
        var name = ""
        var arguments = ""
    }

    private var framer = SSEEventFramer()
    private var tools: [Int: ToolState] = [:]
    private var reasoningContent = ""
    private var currentPhase: AIGenerationPhase?
    private var lastUsage: KimiWireUsage?
    private var responseID: String?
    private var terminalEmitted = false

    func receive(line: String) throws -> [AIStreamEvent] {
        try map(framer.receive(line: line))
    }

    func finish() throws -> [AIStreamEvent] {
        var events = try map(framer.finish())
        if !terminalEmitted { events += try terminalEvents(reason: nil) }
        return events
    }

    private func map(_ frames: [SSEFrame]) throws -> [AIStreamEvent] {
        try frames.flatMap { frame in
            switch frame {
            case .data(let data): return try map(try KimiWireChunk(data: data))
            case .done: return try terminalEvents(reason: nil)
            }
        }
    }

    private func map(_ chunk: KimiWireChunk) throws -> [AIStreamEvent] {
        if let id = chunk.id { responseID = id }
        if let usage = chunk.usage { lastUsage = usage }
        guard let choice = chunk.choices?.first else { return [] }
        var events: [AIStreamEvent] = []
        if let reasoning = choice.delta?.reasoningContent, !reasoning.isEmpty {
            reasoningContent += reasoning
            events += phase(.thinking) + [.reasoningDelta(reasoning)]
        }
        if let text = choice.delta?.content, !text.isEmpty {
            events += phase(.generating) + [.text(text)]
        }
        for call in choice.delta?.toolCalls ?? [] {
            let index = call.index ?? 0
            var item = tools[index] ?? ToolState()
            if let id = call.id { item.id = id }
            if let name = call.function?.name { item.name = name }
            if let arguments = call.function?.arguments { item.arguments += arguments }
            tools[index] = item
        }
        if let reason = choice.finishReason { events += try terminalEvents(reason: reason) }
        return events
    }

    private func terminalEvents(reason: String?) throws -> [AIStreamEvent] {
        guard !terminalEmitted else { return [] }
        terminalEmitted = true
        var events: [AIStreamEvent] = []
        if !reasoningContent.isEmpty {
            let continuation = AIProviderContinuation(
                provider: .kimi,
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
        let searchTools = completedTools.filter {
            $0.name == KimiFormulaContract.webSearchToolName
        }
        // 搜索开启的生产请求已经预执行 Formula，并以 tool_choice=none 合成答案。
        // 再收到模型发起的 web_search 代表契约漂移，不能回到旧 continuation 循环。
        guard searchTools.isEmpty else { throw KimiWireError.unexpectedFormulaToolCall }
        let appTools = completedTools.filter {
            $0.name != KimiFormulaContract.webSearchToolName
        }
        if !appTools.isEmpty {
            events += phase(.usingTool)
            events += appTools.map(AIStreamEvent.toolCall)
        }
        if let usage = lastUsage {
            events.append(.usage(AIUsage(
                inputTokens: usage.promptTokens,
                outputTokens: usage.completionTokens,
                totalTokens: usage.totalTokens
            )))
        }
        if let responseID {
            events.append(.continuation(AIProviderContinuation(
                provider: .kimi,
                kind: "response_id",
                payload: .string(responseID)
            )))
        }
        events.append(.stopReason(stopReason(reason, hasTools: !completedTools.isEmpty)))
        return events
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
