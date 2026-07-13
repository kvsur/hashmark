//
//  AIMessage.swift
//  MarkdownApp
//
//  一条 AI 对话消息（组装请求用）。与具体上游格式无关——
//  ChatGPT/Claude 两个 client 各自把它翻译成对应请求体。
//

import Foundation

struct AIMessage: Equatable {
    enum Role: String {
        case system
        case user
        case assistant
    }

    let role: Role
    let content: String

    init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}
