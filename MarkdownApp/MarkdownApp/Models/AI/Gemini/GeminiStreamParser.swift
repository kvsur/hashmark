//
//  GeminiStreamParser.swift
//  MarkdownApp
//
//  Interactions step.* SSE 到 typed phases、thought、tool、citation 与 continuation 的映射。
//

import Foundation

nonisolated final class GeminiStreamParser {
    private struct PendingFunctionCall {
        let id: String
        let name: String
        let arguments: JSONValue
    }

    private struct StepState {
        var step: GeminiWireStep
        var name: String?
        var arguments: JSONValue?
        var argumentFragments = ""
        var text = ""
        var signature = ""

        init(step: GeminiWireStep) {
            self.step = step
            self.name = step.name
            self.arguments = step.arguments
        }

        mutating func receive(arguments value: JSONValue) {
            if case .string(let fragment) = value {
                argumentFragments += fragment
            } else {
                arguments = value
            }
        }

        var resolvedArguments: JSONValue? {
            guard !argumentFragments.isEmpty else { return arguments }
            guard let data = argumentFragments.data(using: .utf8),
                  let value = try? JSONSerialization.jsonObject(with: data)
            else { return nil }
            return .foundation(value)
        }
    }

    private var framer = SSEEventFramer()
    private var steps: [Int: StepState] = [:]
    private var emittedToolCallIDs: Set<String> = []
    private var emittedCitationIDs: Set<String> = []
    private var pendingFunctionCalls: [PendingFunctionCall] = []
    private var currentPhase: AIGenerationPhase?
    private var sawToolCall = false

    private(set) var completedInteractionID: String?
    private(set) var completedInteractionStatus: String?

    func receive(line: String) throws -> [AIStreamEvent] {
        try map(framer.receive(line: line))
    }

    func finish() throws -> [AIStreamEvent] {
        try map(framer.finish())
    }

    private func map(_ frames: [SSEFrame]) throws -> [AIStreamEvent] {
        try frames.flatMap { frame in
            switch frame {
            case .data(let data): return try map(GeminiWireEvent(data: data))
            case .done: return []
            }
        }
    }

    private func map(_ event: GeminiWireEvent) throws -> [AIStreamEvent] {
        switch event {
        case .interactionCreated:
            return phase(.connecting)
        case .stepStart(let index, let step):
            var state = StepState(step: step)
            state.text = step.summary?.compactMap(\.text).joined() ?? ""
            state.signature = step.signature ?? ""
            steps[index] = state
            return phaseForStep(step.type, requestID: step.id)
        case .stepDelta(let index, let type, let text, let signature, let name, _,
                        let arguments, let annotations):
            if let signature { steps[index]?.signature += signature }
            if let name { steps[index]?.name = name }
            if let arguments { steps[index]?.receive(arguments: arguments) }
            var events = annotations.compactMap(citation)
            if let text, !text.isEmpty {
                steps[index]?.text += text
                if steps[index]?.step.type == "thought" || type == "thought_summary" {
                    events = phase(.thinking) + [.reasoningDelta(text)] + events
                } else {
                    events = phase(.generating) + [.text(text)] + events
                }
            }
            // Function deltas may announce the name before their arguments. Hold the
            // assembled call until interaction.completed makes the continuation reusable.
            return events
        case .stepStop(let index, let finalStep):
            if let finalStep {
                steps[index]?.step = finalStep
                steps[index]?.name = finalStep.name ?? steps[index]?.name
                if let arguments = finalStep.arguments {
                    steps[index]?.receive(arguments: arguments)
                }
            }
            guard let state = steps.removeValue(forKey: index) else { return [] }
            return finalize(state)
        case .interactionCompleted(let interaction):
            completedInteractionID = interaction.id
            completedInteractionStatus = interaction.status
            var events = pendingFunctionCalls.flatMap {
                toolCall(id: $0.id, name: $0.name, arguments: $0.arguments)
            }
            pendingFunctionCalls.removeAll()
            events += interaction.steps?.flatMap(finalEvents) ?? []
            if let usage = interaction.usage { events.append(.usage(domainUsage(usage))) }
            events.append(.continuation(AIProviderContinuation(
                provider: .gemini,
                kind: "interaction_id",
                payload: .string(interaction.id)
            )))
            events.append(.stopReason(sawToolCall ? .toolUse : .endTurn))
            return events
        case .interactionFailed(let code, let message):
            throw GeminiWireError.remote(code: code, message: message)
        case .unknown:
            return []
        }
    }

    private func finalize(_ state: StepState) -> [AIStreamEvent] {
        switch state.step.type {
        case "thought":
            let summary = state.text
            let payload: JSONValue = .object([
                "type": .string("thought"),
                "summary": .array(summary.isEmpty ? [] : [.object([
                    "type": .string("text"),
                    "text": .string(summary)
                ])]),
                "signature": .string(state.signature)
            ])
            return [.reasoningBlock(AIReasoningBlock(
                visibleText: summary,
                continuation: AIProviderContinuation(
                    provider: .gemini,
                    kind: "interaction_step",
                    payload: payload
                )
            ))]
        case "function_call":
            guard let name = state.name,
                  let arguments = state.resolvedArguments
            else { return [] }
            pendingFunctionCalls.append(PendingFunctionCall(
                id: state.step.id ?? state.step.callID ?? name,
                name: name,
                arguments: arguments
            ))
            // Gemini emits interaction.completed immediately after a requires_action
            // step. Hold the client tool call until then so the Adapter can persist the
            // interaction ID before the UI stops consuming this stream.
            return []
        case "google_search_call", "google_search_result", "file_search_call", "file_search_result":
            return searchStarted(requestID: state.step.id)
        case "model_output":
            return state.step.content?.flatMap { $0.annotations?.compactMap(citation) ?? [] } ?? []
        default:
            return []
        }
    }

    private func finalEvents(_ step: GeminiWireStep) -> [AIStreamEvent] {
        switch step.type {
        case "function_call":
            guard let name = step.name else { return [] }
            return toolCall(
                id: step.id ?? step.callID ?? name,
                name: name,
                arguments: step.arguments ?? .object([:])
            )
        case "google_search_call", "google_search_result", "file_search_call", "file_search_result":
            return searchStarted(requestID: step.id)
        case "model_output":
            return step.content?.flatMap { $0.annotations?.compactMap(citation) ?? [] } ?? []
        default:
            return []
        }
    }

    private func toolCall(id: String, name: String, arguments: JSONValue) -> [AIStreamEvent] {
        guard emittedToolCallIDs.insert(id).inserted else { return [] }
        sawToolCall = true
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try? encoder.encode(arguments)
        let json = data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return phase(.usingTool) + [.toolCall(AIToolCall(id: id, name: name, arguments: json))]
    }

    private func citation(_ annotation: GeminiWireAnnotation) -> AIStreamEvent? {
        guard annotation.type == nil || annotation.type == "url_citation",
              let rawURL = annotation.url,
              let url = AISearchSourceValidator.url(rawURL)
        else { return nil }
        let id = "gemini|\(url.absoluteString)"
        guard emittedCitationIDs.insert(id).inserted else { return nil }
        let marker: String?
        if let start = annotation.startIndex, let end = annotation.endIndex {
            marker = "\(start):\(end)"
        } else {
            marker = nil
        }
        return .search(.citation(AISearchCitation(
            id: id,
            title: annotation.title ?? url.host ?? rawURL,
            url: url,
            publisher: url.host,
            marker: marker,
            provider: .gemini,
            sourceIdentity: url.absoluteString,
            startIndex: annotation.startIndex,
            endIndex: annotation.endIndex
        )))
    }

    private func phaseForStep(_ type: String, requestID: String?) -> [AIStreamEvent] {
        switch type {
        case "thought": phase(.thinking)
        case "google_search_call", "google_search_result", "file_search_call", "file_search_result":
            searchStarted(requestID: requestID)
        case "function_call": phase(.usingTool)
        case "model_output": phase(.generating)
        default: []
        }
    }

    private func phase(_ next: AIGenerationPhase) -> [AIStreamEvent] {
        guard currentPhase != next else { return [] }
        currentPhase = next
        return [.phase(next)]
    }

    private func searchStarted(requestID: String?) -> [AIStreamEvent] {
        phase(.searching) + [.search(.started(AISearchActivity(
            provider: .gemini,
            query: nil,
            requestID: requestID
        )))]
    }

    private func domainUsage(_ usage: GeminiWireUsage) -> AIUsage {
        AIUsage(
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            totalTokens: usage.totalTokens
        )
    }
}
