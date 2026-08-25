//
//  AIStreamEvent.swift
//  MarkdownApp
//
//  六家 Adapter 输出的中立事件。只有 text 能进入 Markdown；reasoning、source、
//  file、usage 和 Provider continuation 始终旁路。
//

import Foundation

nonisolated enum AIStreamStopReason: Equatable {
    case endTurn
    case toolUse
    case maxTokens
    case stopSequence
    case pauseTurn
    case refusal
    case unknown(String)
}

nonisolated enum AIStreamEvent: Equatable {
    case phase(AIGenerationPhase)
    case reasoningDelta(String)
    case reasoningBlock(AIReasoningBlock)
    case text(String)
    case toolCall(AIToolCall)
    case search(AISearchEvent)
    case fileState(AIFileState)
    case usage(AIUsage)
    case continuation(AIProviderContinuation)
    case stopReason(AIStreamStopReason)

    var isWebSearchExecutionEvidence: Bool {
        if case .search = self { true } else { false }
    }

    var isAnswerText: Bool {
        if case .text = self { true } else { false }
    }
}
