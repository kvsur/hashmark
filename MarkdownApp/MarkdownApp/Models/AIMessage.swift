//
//  AIMessage.swift
//  MarkdownApp
//
//  一条 AI 对话消息（组装请求用）。与具体上游格式无关——
//  ChatGPT/Claude 两个 client 各自把它翻译成对应请求体。
//  为支持 function tool calling，消息可携带：assistant 发起的工具调用（toolCalls），
//  或对某次调用的回答结果（tool 角色 + toolCallId）。
//

import Foundation

/// 模型发起的一次工具调用（供应商无关的中立表示）。
struct AIToolCall: Equatable {
    /// 供应商给的调用 id（OpenAI tool_call.id / Anthropic tool_use.id），回填结果时要带上。
    let id: String
    /// 工具名。
    let name: String
    /// 模型给的入参，原始 JSON 字符串（如 `{"question":"...","answer_type":"text"}`）。
    let arguments: String
}

struct AIMessage: Equatable {
    enum Role: String {
        case system
        case user
        case assistant
        case tool        // 工具调用的回答结果（OpenAI role:tool / Anthropic user+tool_result）
    }

    let role: Role
    /// 文本内容；assistant 携带工具调用时可为空，tool 结果消息里是答案文本。
    let content: String
    /// 仅 assistant：本条消息里模型发起的工具调用。
    let toolCalls: [AIToolCall]
    /// 仅 tool 结果消息：对应被回答的那次调用 id。
    let toolCallId: String?
    /// 仅 user：随本条消息发送的图片附件（多模态）。默认空——空时两家 client 保持旧的纯字符串
    /// content 形状不变（向后兼容），非空才升级为 content blocks。documentReference 类附件不在这里，
    /// 它已在 AIAction 装配阶段拼进 content 文本。
    let attachments: [AIAttachment]

    init(role: Role, content: String, toolCalls: [AIToolCall] = [], toolCallId: String? = nil, attachments: [AIAttachment] = []) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.attachments = attachments
    }

    /// 本条 user 消息携带的图片 JPEG（供 client 序列化图片块）。
    var imageAttachments: [Data] { attachments.compactMap(\.imageJPEG) }
    /// 本条 user 消息携带的 PDF（文件名, 数据）（供 client 序列化文档块）。
    /// 从 attachments 派生而非另存元组数组——元组不满足 Equatable，会破坏 AIMessage 的合成实现。
    var pdfAttachments: [(name: String, data: Data)] { attachments.compactMap(\.pdfPayload) }

    /// 便捷构造：assistant 发起工具调用（可带同轮已产出的文本）。
    static func assistant(text: String, toolCalls: [AIToolCall]) -> AIMessage {
        AIMessage(role: .assistant, content: text, toolCalls: toolCalls)
    }

    /// 便捷构造：对某次工具调用的回答结果。
    static func toolResult(callId: String, content: String) -> AIMessage {
        AIMessage(role: .tool, content: content, toolCallId: callId)
    }
}
