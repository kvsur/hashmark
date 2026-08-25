//
//  AIPresentationState.swift
//  MarkdownApp
//
//  Provider-neutral presentation reducer. Wire event names never reach SwiftUI;
//  this state is the single source of truth for the visible generation lifecycle.
//

import Foundation

nonisolated enum AIPresentationPhase: Equatable {
    case idle
    case preparingAttachments
    case uploading
    case connecting
    case thinking
    case searching
    case usingTool
    case generating
    case finalizing
    case awaitingInput
    case completed
    case cancelled
    case interrupted(String)
    case failed(String)

    var isActive: Bool {
        switch self {
        case .preparingAttachments, .uploading, .connecting, .thinking,
             .searching, .usingTool, .generating, .finalizing:
            true
        case .idle, .awaitingInput, .completed, .cancelled, .interrupted, .failed:
            false
        }
    }

    var isTerminal: Bool {
        switch self {
        case .completed, .cancelled, .interrupted, .failed: true
        default: false
        }
    }
}

nonisolated struct AIPresentationState: Equatable {
    private(set) var phase: AIPresentationPhase = .idle
    private(set) var hasStartedAnswer = false

    mutating func beginTurn(hasAttachments: Bool) {
        hasStartedAnswer = false
        phase = hasAttachments ? .preparingAttachments : .connecting
    }

    mutating func apply(_ generationPhase: AIGenerationPhase) {
        guard !phase.isTerminal else { return }
        phase = switch generationPhase {
        case .preparingAttachments: .preparingAttachments
        case .uploading: .uploading
        case .connecting: .connecting
        case .thinking: hasStartedAnswer ? .generating : .thinking
        case .searching: .searching
        case .usingTool: .usingTool
        case .generating: .generating
        case .finalizing: .finalizing
        }
    }

    mutating func receiveReasoning() {
        guard !phase.isTerminal, !hasStartedAnswer else { return }
        phase = .thinking
    }

    mutating func receiveAnswerText() {
        guard !phase.isTerminal else { return }
        hasStartedAnswer = true
        phase = .generating
    }

    mutating func awaitInput() {
        guard !phase.isTerminal else { return }
        phase = .awaitingInput
    }

    mutating func finalizing() {
        guard !phase.isTerminal else { return }
        phase = .finalizing
    }

    mutating func complete() { phase = .completed }
    mutating func cancel() { phase = .cancelled }
    mutating func interrupt(_ message: String) { phase = .interrupted(message) }
    mutating func fail(_ message: String) { phase = .failed(message) }
}

/// Per-response disclosure policy. The automatic collapse is a one-time default;
/// after the reader chooses a state, streaming never overrides that choice.
nonisolated struct AIReasoningDisclosureState: Equatable {
    private(set) var isExpanded = true
    private(set) var userChoice: Bool?

    mutating func beginTurn() {
        isExpanded = true
        userChoice = nil
    }

    mutating func answerStarted() {
        guard userChoice == nil else { return }
        isExpanded = false
    }

    mutating func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
        userChoice = expanded
    }
}

/// Reader ownership for an updating answer. Streaming follows only while the reader
/// remains near the bottom; jumping to latest explicitly returns ownership to the app.
nonisolated struct AIStreamingScrollState: Equatable {
    private(set) var followsLatest = true

    mutating func beginTurn() { followsLatest = true }
    mutating func readerPositionChanged(isNearBottom: Bool) { followsLatest = isNearBottom }
    mutating func jumpToLatest() { followsLatest = true }
}
