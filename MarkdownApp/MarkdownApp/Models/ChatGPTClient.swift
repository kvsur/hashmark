//
//  ChatGPTClient.swift
//  MarkdownApp
//
//  OpenAI 兼容格式（/chat/completions，Bearer）。支持 function tools：
//  - 请求：tools=[{type:function,function:{name,description,parameters}}]；消息可带 tool_calls / role:tool。
//  - 流式：choices[].delta.content 取文本；choices[].delta.tool_calls[] 按 index 累积 id/name/arguments，
//    finish_reason=="tool_calls" 或 [DONE] 时产出完整的 toolCall。
//  请求体统一用 JSONValue 拼装，从容表达 assistant.tool_calls 与 tool 结果等异构形状。
//

import Foundation

struct ChatGPTClient: AIClient {
    let config: AIConfig

    func stream(messages: [AIMessage], tools: [AITool]) -> AsyncThrowingStream<AIStreamEvent, Error> {
        SSEStream.streamWithToolFallback(
            tools: tools,
            makeRequest: { try makeRequest(messages, tools: $0) },
            makeParser: { OpenAIStreamParser() }
        )
    }

    private func makeRequest(_ messages: [AIMessage], tools: [AITool]) throws -> URLRequest {
        guard let url = aiEndpointURL(base: config.baseURL, endpoint: "chat/completions") else {
            throw AIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body(messages, tools: tools))
        return request
    }

    /// 组装请求体（JSONValue）。
    private func body(_ messages: [AIMessage], tools: [AITool]) -> JSONValue {
        var obj: [String: JSONValue] = [
            "model": .string(config.model),
            "messages": .array(messages.map(Self.serialize)),
            "stream": .bool(true)
        ]
        if !tools.isEmpty {
            obj["tools"] = .array(tools.map { tool in
                .object([
                    "type": .string("function"),
                    "function": .object([
                        "name": .string(tool.name),
                        "description": .string(tool.description),
                        "parameters": tool.parameters
                    ])
                ])
            })
        }
        return .object(obj)
    }

    /// 把一条中立消息翻译成 OpenAI 消息对象。
    private static func serialize(_ msg: AIMessage) -> JSONValue {
        switch msg.role {
        case .system:
            return .object(["role": .string(msg.role.rawValue), "content": .string(msg.content)])
        case .user:
            // 图片用 image_url(data URI)，PDF 用 file(file_data data URI)。
            let mediaBlocks: [JSONValue] =
                msg.imageAttachments.map { data in
                    .object([
                        "type": .string("image_url"),
                        "image_url": .object([
                            "url": .string("data:image/jpeg;base64,\(data.base64EncodedString())")
                        ])
                    ])
                }
                + msg.pdfAttachments.map { pdf in
                    .object([
                        "type": .string("file"),
                        "file": .object([
                            "filename": .string(pdf.name),
                            "file_data": .string("data:application/pdf;base64,\(pdf.data.base64EncodedString())")
                        ])
                    ])
                }
            // 无富媒体附件：保持旧的纯字符串 content 形状（向后兼容，逐字节不变）。
            guard !mediaBlocks.isEmpty else {
                return .object(["role": .string("user"), "content": .string(msg.content)])
            }
            let content = MultimodalContent.userContent(text: msg.content, mediaBlocks: mediaBlocks)
            return .object(["role": .string("user"), "content": content])
        case .assistant where !msg.toolCalls.isEmpty:
            return .object([
                "role": .string("assistant"),
                // 有工具调用时 content 可为空，用 null 表达。
                "content": msg.content.isEmpty ? .null : .string(msg.content),
                "tool_calls": .array(msg.toolCalls.map { tc in
                    .object([
                        "id": .string(tc.id),
                        "type": .string("function"),
                        "function": .object([
                            "name": .string(tc.name),
                            "arguments": .string(tc.arguments)
                        ])
                    ])
                })
            ])
        case .assistant:
            return .object(["role": .string("assistant"), "content": .string(msg.content)])
        case .tool:
            return .object([
                "role": .string("tool"),
                "tool_call_id": .string(msg.toolCallId ?? ""),
                "content": .string(msg.content)
            ])
        }
    }
}

// MARK: - 流式解析（有状态）

/// 累积 OpenAI 流：文本增量即时产出；工具调用按 index 累积，末尾一次性产出完整 toolCall。
private final class OpenAIStreamParser: SSEEventParser {
    private struct Accum { var id = ""; var name = ""; var args = "" }
    private var accum: [Int: Accum] = [:]
    private var flushed = false

    func consume(_ line: String) -> (events: [AIStreamEvent], done: Bool) {
        guard let payload = SSEStream.dataPayload(line) else { return ([], false) }
        if payload == "[DONE]" { return (flushTools(), true) }
        guard let data = payload.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(Chunk.self, from: data),
              let choice = chunk.choices.first
        else { return ([], false) }

        var events: [AIStreamEvent] = []
        if let text = choice.delta?.content, !text.isEmpty {
            events.append(.text(text))
        }
        if let calls = choice.delta?.toolCalls {
            for call in calls {
                var item = accum[call.index] ?? Accum()
                if let id = call.id { item.id = id }
                if let name = call.function?.name { item.name = name }
                if let args = call.function?.arguments { item.args += args }
                accum[call.index] = item
            }
        }
        if choice.finishReason == "tool_calls" {
            events.append(contentsOf: flushTools())
        }
        return (events, false)
    }

    /// 把累积到的工具调用产出成事件（只产出一次，名字为空的丢弃）。
    private func flushTools() -> [AIStreamEvent] {
        guard !flushed, !accum.isEmpty else { return [] }
        flushed = true
        return accum.keys.sorted().compactMap { index in
            guard let item = accum[index], !item.name.isEmpty else { return nil }
            let id = item.id.isEmpty ? "call_\(index)" : item.id
            return .toolCall(AIToolCall(id: id, name: item.name, arguments: item.args))
        }
    }

    private struct Chunk: Decodable {
        let choices: [Choice]
        struct Choice: Decodable {
            let delta: Delta?
            let finishReason: String?
            enum CodingKeys: String, CodingKey {
                case delta
                case finishReason = "finish_reason"
            }
            struct Delta: Decodable {
                let content: String?
                let toolCalls: [ToolCall]?
                enum CodingKeys: String, CodingKey {
                    case content
                    case toolCalls = "tool_calls"
                }
            }
            struct ToolCall: Decodable {
                let index: Int
                let id: String?
                let function: Function?
                struct Function: Decodable {
                    let name: String?
                    let arguments: String?
                }
            }
        }
    }
}
