//
//  AnthropicStreamParser.swift
//  MarkdownApp
//
//  Anthropic SSE framing、content block 顺序与 opaque continuation 映射。
//

import Foundation

nonisolated final class AnthropicStreamParser {
    private struct BlockState {
        let type: String
        let id: String?
        let name: String?
        var text: String
        var signature: String
        var partialJSON: String
        let opaqueData: String?
        let content: JSONValue?
    }

    private var framer = SSEEventFramer()
    private var blocks: [Int: BlockState] = [:]
    private var emittedCitationIDs: Set<String> = []
    private var currentPhase: AIGenerationPhase?
    private var pendingStopReason: AIStreamStopReason?
    private var stopEmitted = false

    func receive(line: String) throws -> [AIStreamEvent] {
        try map(framer.receive(line: line))
    }

    func finish() throws -> [AIStreamEvent] {
        try map(framer.finish())
    }

    private func map(_ frames: [SSEFrame]) throws -> [AIStreamEvent] {
        try frames.flatMap { frame in
            switch frame {
            case .data(let data): return try map(AnthropicWireEvent(data: data))
            case .done: return []
            }
        }
    }

    private func map(_ event: AnthropicWireEvent) -> [AIStreamEvent] {
        switch event {
        case .messageStart(let message):
            var events = phase(.connecting)
            if let usage = message.usage { events.append(.usage(domainUsage(usage))) }
            return events
        case .blockStart(let index, let block):
            blocks[index] = BlockState(
                type: block.type,
                id: block.id,
                name: block.name,
                text: block.text ?? block.thinking ?? "",
                signature: block.signature ?? "",
                partialJSON: "",
                opaqueData: block.data,
                content: block.content
            )
            var events: [AIStreamEvent] = block.citations?.compactMap(citation) ?? []
            switch block.type {
            case "thinking", "redacted_thinking": events = phase(.thinking) + events
            case "tool_use": events = phase(.usingTool) + events
            case "server_tool_use", "web_search_tool_result":
                events = searchStarted(requestID: block.id) + searchResultCitations(block.content) + events
            default: break
            }
            return events
        case .textDelta(let index, let text):
            blocks[index]?.text += text
            return phase(.generating) + [.text(text)]
        case .thinkingDelta(let index, let text):
            blocks[index]?.text += text
            return phase(.thinking) + [.reasoningDelta(text)]
        case .signatureDelta(let index, let signature):
            blocks[index]?.signature += signature
            return []
        case .inputJSONDelta(let index, let fragment):
            blocks[index]?.partialJSON += fragment
            return blocks[index]?.type == "server_tool_use"
                ? searchStarted(requestID: blocks[index]?.id)
                : []
        case .citationDelta(_, let value):
            return citation(value).map { [$0] } ?? []
        case .blockStop(let index):
            guard let block = blocks.removeValue(forKey: index) else { return [] }
            return finalize(block)
        case .messageDelta(let reason, let usage):
            pendingStopReason = stopReason(reason)
            return usage.map { [.usage(domainUsage($0))] } ?? []
        case .messageStop:
            guard !stopEmitted else { return [] }
            stopEmitted = true
            return [.stopReason(pendingStopReason ?? .endTurn)]
        case .ping:
            return []
        }
    }

    private func finalize(_ block: BlockState) -> [AIStreamEvent] {
        switch block.type {
        case "thinking":
            let payload: JSONValue = .object([
                "type": .string("thinking"),
                "thinking": .string(block.text),
                "signature": .string(block.signature)
            ])
            return [.reasoningBlock(AIReasoningBlock(
                visibleText: block.text,
                continuation: AIProviderContinuation(
                    provider: .anthropic,
                    kind: "thinking_block",
                    payload: payload
                )
            ))]
        case "redacted_thinking":
            let payload: JSONValue = .object([
                "type": .string("redacted_thinking"),
                "data": .string(block.opaqueData ?? "")
            ])
            return [.reasoningBlock(AIReasoningBlock(
                visibleText: "",
                continuation: AIProviderContinuation(
                    provider: .anthropic,
                    kind: "thinking_block",
                    payload: payload
                )
            ))]
        case "tool_use":
            guard let name = block.name else { return [] }
            return [.toolCall(AIToolCall(
                id: block.id ?? "toolu_unknown",
                name: name,
                arguments: block.partialJSON.isEmpty ? "{}" : block.partialJSON
            ))]
        case "server_tool_use":
            return searchStarted(requestID: block.id)
        case "web_search_tool_result":
            let payload: JSONValue = .object([
                "type": .string("web_search_tool_result"),
                "tool_use_id": .string(block.id ?? ""),
                "content": block.content ?? .array([])
            ])
            return searchResultCitations(block.content) + [.continuation(AIProviderContinuation(
                provider: .anthropic,
                kind: "server_tool_result",
                payload: payload
            ))]
        default:
            return []
        }
    }

    private func searchResultCitations(_ value: JSONValue?) -> [AIStreamEvent] {
        guard case .array(let items) = value else { return [] }
        return items.compactMap { item in
            guard case .object(let object) = item,
                  case .string(let rawURL)? = object["url"],
                  let url = AISearchSourceValidator.url(rawURL)
            else { return nil }
            let title: String
            if case .string(let value)? = object["title"] { title = value }
            else { title = url.host ?? rawURL }
            return citation(title: title, url: url, marker: nil)
        }
    }

    private func citation(_ value: AnthropicWireCitation) -> AIStreamEvent? {
        guard value.type == nil || value.type == "web_search_result_location",
              let rawURL = value.url,
              let url = AISearchSourceValidator.url(rawURL)
        else { return nil }
        return citation(
            title: value.title ?? url.host ?? rawURL,
            url: url,
            marker: value.encryptedIndex
        )
    }

    private func citation(title: String, url: URL, marker: String?) -> AIStreamEvent? {
        let id = "anthropic|\(url.absoluteString)"
        guard emittedCitationIDs.insert(id).inserted else { return nil }
        return .search(.citation(AISearchCitation(
            id: id,
            title: title,
            url: url,
            publisher: url.host,
            marker: marker,
            provider: .anthropic,
            sourceIdentity: url.absoluteString
        )))
    }

    private func phase(_ next: AIGenerationPhase) -> [AIStreamEvent] {
        guard currentPhase != next else { return [] }
        currentPhase = next
        return [.phase(next)]
    }

    private func searchStarted(requestID: String?) -> [AIStreamEvent] {
        phase(.searching) + [.search(.started(AISearchActivity(
            provider: .anthropic,
            query: nil,
            requestID: requestID
        )))]
    }

    private func domainUsage(_ usage: AnthropicWireUsage) -> AIUsage {
        let total = usage.inputTokens.flatMap { input in usage.outputTokens.map { input + $0 } }
        return AIUsage(
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            totalTokens: total
        )
    }

    private func stopReason(_ value: String?) -> AIStreamStopReason? {
        switch value {
        case "end_turn": .endTurn
        case "tool_use": .toolUse
        case "max_tokens": .maxTokens
        case "stop_sequence": .stopSequence
        case "pause_turn": .pauseTurn
        case "refusal": .refusal
        case .some(let value): .unknown(value)
        case nil: nil
        }
    }
}
