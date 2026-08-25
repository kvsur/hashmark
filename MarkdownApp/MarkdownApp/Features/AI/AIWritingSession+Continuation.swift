//
//  AIWritingSession+Continuation.swift
//  MarkdownApp
//
//  Native search continuation, tool handoff, terminal policy, and final commit.
//

import Foundation

extension AIWritingSession {
    func acceptsNativeSearchContinuation(_ value: AISearchContinuation) -> Bool {
        guard value.provider == .kimi,
              !value.callID.isEmpty,
              !value.arguments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let resolved = config.resolvedProvider,
              resolved.provider == .kimi,
              resolved.effectiveCapabilities.webSearch.isEnabled,
              resolved.manifest.webSearch.automaticContinuationToolName == value.toolName
        else { return false }
        return true
    }

    func resolveNativeSearchContinuations(
        _ continuations: [AISearchContinuation],
        using adapter: AIProviderAdapter?
    ) async throws -> [(continuation: AISearchContinuation, result: String)] {
        var resolved: [(continuation: AISearchContinuation, result: String)] = []
        for continuation in continuations {
            let result: String
            if let adapter {
                result = try await adapter.resolveNativeSearch(continuation)
            } else {
                // Scripted session tests have no concrete Provider Adapter. Production
                // Kimi requests always execute the Formula through KimiAdapter.
                result = continuation.arguments
            }
            AIDiagnostics.automaticWebSearchContinuation(
                name: continuation.toolName,
                turn: resolved.count + 1
            )
            resolved.append((continuation, result))
        }
        return resolved
    }

    func prepareNativeSearchContinuations(
        _ resolved: [(continuation: AISearchContinuation, result: String)],
        transportMessages: [AIMessage]
    ) -> [AIMessage] {
        let calls = resolved.map { item in
            AIToolCall(
                id: item.continuation.callID,
                name: item.continuation.toolName,
                arguments: item.continuation.arguments
            )
        }
        let assistant = AIMessage.assistant(
            text: text,
            toolCalls: calls,
            reasoningBlocks: reasoningBlocks
        )
        let results = zip(calls, resolved).map { call, item in
            AIMessage.toolResult(
                callId: call.id,
                name: call.name,
                content: item.result
            )
        }
        messages.append(assistant)
        messages.append(contentsOf: results)
        deltaCoalescer.discard()
        text = ""
        reasoningText = ""
        reasoningBlocks = []
        didCommit = false
        phase = .loading
        presentationState.beginTurn(hasAttachments: false)
        return transportMessages + [assistant] + results
    }

    func completeSearchIfNeeded() {
        let provider: AIProvider?
        switch searchTimeline.state {
        case .searching(let value, _), .awaitingContinuation(let value): provider = value
        case .idle, .completed: provider = nil
        }
        if let provider { searchTimeline.apply(.completed(provider)) }
    }

    func handleToolCall(_ call: AIToolCall) {
        guard call.name == ClarifyTool.name,
              let request = ClarifyRequest(argumentsJSON: call.arguments) else {
            let reason = call.name == ClarifyTool.name
                ? "invalid-clarify-arguments"
                : "unsupported-tool-name"
            AIDiagnostics.unrecognizedTool(name: call.name, reason: reason)
            let message = LocalizationController.string(
                "The AI returned something unrecognizable. Try again or rephrase your request."
            )
            if hasContent {
                interruptedReason = message
                presentationState.interrupt(message)
                phase = .interrupted(message)
            } else {
                presentationState.fail(message)
                phase = .error(message)
            }
            return
        }
        messages.append(.assistant(
            text: text,
            toolCalls: [call],
            reasoningBlocks: reasoningBlocks
        ))
        pendingToolCall = call
        presentationState.awaitInput()
        phase = .awaitingAnswer(request)
    }

    var diagnosticPhaseName: String {
        switch phase {
        case .idle: "idle"
        case .loading: "loading"
        case .reasoning: "reasoning"
        case .streaming: "streaming"
        case .awaitingAnswer: "awaiting-answer"
        case .done: "done"
        case .cancelled: "cancelled"
        case .interrupted: "interrupted"
        case .error: "error"
        }
    }

    func terminalInterruptionMessage() -> String? {
        if text.isEmpty {
            return LocalizationController.string("The AI did not return an answer. Try again.")
        }
        switch stopReason {
        case .maxTokens:
            return LocalizationController.string(
                "The answer reached the model's length limit. Try again with a shorter request."
            )
        case .pauseTurn:
            return LocalizationController.string("The AI paused before finishing. Try again.")
        case .refusal:
            return LocalizationController.string("The AI couldn't complete this request.")
        case .unknown:
            return LocalizationController.string("The AI stopped unexpectedly. Try again.")
        case .none, .endTurn, .toolUse, .stopSequence:
            return nil
        }
    }

    func commitAssistantTurn() {
        guard !didCommit, !text.isEmpty || !reasoningBlocks.isEmpty else { return }
        didCommit = true
        if !text.isEmpty { committedText = text }
        messages.append(AIMessage(
            role: .assistant,
            content: text,
            reasoningBlocks: reasoningBlocks
        ))
    }
}
