//
//  GeminiInteractionState.swift
//  MarkdownApp
//
//  previous_interaction_id 及已消费消息数量只属于当前 Gemini Adapter 会话。
//

import Foundation

actor GeminiInteractionState {
    struct Context {
        let previousInteractionID: String?
        let consumedMessageCount: Int
    }

    private var previousInteractionID: String?
    private var consumedMessageCount = 0

    func context(totalMessageCount: Int) -> Context {
        guard totalMessageCount >= consumedMessageCount else {
            previousInteractionID = nil
            consumedMessageCount = 0
            return Context(previousInteractionID: nil, consumedMessageCount: 0)
        }
        return Context(
            previousInteractionID: previousInteractionID,
            consumedMessageCount: consumedMessageCount
        )
    }

    func complete(interactionID: String, consumedMessageCount: Int) {
        previousInteractionID = interactionID
        self.consumedMessageCount = consumedMessageCount
    }
}
