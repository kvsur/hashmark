//
//  OpenAIResponsesSessionState.swift
//  MarkdownApp
//
//  previous_response_id 只属于一个 OpenAI Adapter 会话，不能存进通用消息正文。
//

import Foundation

actor OpenAIResponsesSessionState {
    struct Context {
        let previousResponseID: String?
        let consumedMessageCount: Int
    }

    private var previousResponseID: String?
    private var consumedMessageCount = 0

    func context(totalMessageCount: Int) -> Context {
        guard totalMessageCount >= consumedMessageCount else {
            previousResponseID = nil
            consumedMessageCount = 0
            return Context(previousResponseID: nil, consumedMessageCount: 0)
        }
        return Context(
            previousResponseID: previousResponseID,
            consumedMessageCount: consumedMessageCount
        )
    }

    func complete(responseID: String, consumedMessageCount: Int) {
        previousResponseID = responseID
        self.consumedMessageCount = consumedMessageCount
    }
}
