//
//  ClaudeClient.swift
//  MarkdownApp
//
//  Anthropic 兼容格式（/messages，x-api-key + anthropic-version）。支持 function tools：
//  - 请求：tools=[{name,description,input_schema}]；system 抽为顶层字段；
//    assistant 的 tool_use 与用户的 tool_result 都用 content blocks 表达。
//  - 流式：content_block_delta.text_delta 取文本；content_block_start(tool_use) 起 → input_json_delta
//    累积 partial_json → content_block_stop 产出 toolCall；message_stop 结束。
//

import Foundation

struct ClaudeClient: AIClient {
    let config: AIConfig
    /// Anthropic 要求必填 max_tokens；给一个足够大的默认值。
    private let maxTokens = 4096
    private let anthropicVersion = "2023-06-01"

    func stream(messages: [AIMessage], tools: [AITool]) -> AsyncThrowingStream<AIStreamEvent, Error> {
        SSEStream.streamWithToolFallback(
            tools: tools,
            makeRequest: { try makeRequest(messages, tools: $0) },
            makeParser: { AnthropicStreamParser() }
        )
    }

    private func makeRequest(_ messages: [AIMessage], tools: [AITool]) throws -> URLRequest {
        guard let url = aiEndpointURL(base: config.baseURL, endpoint: "messages") else {
            throw AIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONEncoder().encode(body(messages, tools: tools))
        return request
    }

    private func body(_ messages: [AIMessage], tools: [AITool]) -> JSONValue {
        // system 是顶层字段；messages 里只保留 user/assistant/tool。
        let system = messages.filter { $0.role == .system }
            .map(\.content).joined(separator: "\n\n")
        let turns = messages.filter { $0.role != .system }.map(Self.serialize)

        var obj: [String: JSONValue] = [
            "model": .string(config.model),
            "max_tokens": .number(Double(maxTokens)),
            "messages": .array(turns),
            "stream": .bool(true)
        ]
        if !system.isEmpty { obj["system"] = .string(system) }
        if !tools.isEmpty {
            obj["tools"] = .array(tools.map { tool in
                .object([
                    "name": .string(tool.name),
                    "description": .string(tool.description),
                    "input_schema": tool.parameters
                ])
            })
        }
        return .object(obj)
    }

    /// 把一条中立消息翻译成 Anthropic 消息（tool 结果映射为带 tool_result block 的 user 消息）。
    private static func serialize(_ msg: AIMessage) -> JSONValue {
        switch msg.role {
        case .user, .system:
            return .object(["role": .string("user"), "content": .string(msg.content)])
        case .assistant where !msg.toolCalls.isEmpty:
            // 同一条 assistant 可能既有文本又有 tool_use，用 content blocks 数组表达。
            var blocks: [JSONValue] = []
            if !msg.content.isEmpty {
                blocks.append(.object(["type": .string("text"), "text": .string(msg.content)]))
            }
            for tc in msg.toolCalls {
                blocks.append(.object([
                    "type": .string("tool_use"),
                    "id": .string(tc.id),
                    "name": .string(tc.name),
                    // input 必须是 JSON 对象；模型给的 arguments 是字符串，解析回对象，失败则空对象。
                    "input": parseObject(tc.arguments)
                ]))
            }
            return .object(["role": .string("assistant"), "content": .array(blocks)])
        case .assistant:
            return .object(["role": .string("assistant"), "content": .string(msg.content)])
        case .tool:
            return .object([
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("tool_result"),
                        "tool_use_id": .string(msg.toolCallId ?? ""),
                        "content": .string(msg.content)
                    ])
                ])
            ])
        }
    }

    /// 把 arguments 字符串还原成 JSONValue 对象；非法则空对象（Anthropic 的 input 必须是对象）。
    private static func parseObject(_ json: String) -> JSONValue {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .object([:]) }
        return jsonValue(from: obj)
    }

    /// 递归把 Foundation JSON 对象转成 JSONValue（仅用于回填 tool_use.input，规模很小）。
    private static func jsonValue(from any: Any) -> JSONValue {
        switch any {
        case let dict as [String: Any]:
            return .object(dict.mapValues(jsonValue(from:)))
        case let array as [Any]:
            return .array(array.map(jsonValue(from:)))
        case let str as String:
            return .string(str)
        case let bool as Bool:
            return .bool(bool)
        case let num as NSNumber:
            return .number(num.doubleValue)
        default:
            return .null
        }
    }
}

// MARK: - 流式解析（有状态）

/// 累积 Anthropic 流：text_delta 即时产出；tool_use 块从 content_block_start 起，
/// 逐段累积 input_json_delta.partial_json，到 content_block_stop 时产出完整 toolCall。
private final class AnthropicStreamParser: SSEEventParser {
    private struct ToolBlock { let id: String; let name: String; var json: String }
    private var toolBlocks: [Int: ToolBlock] = [:]

    func consume(_ line: String) -> (events: [AIStreamEvent], done: Bool) {
        guard let payload = SSEStream.dataPayload(line),
              let data = payload.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(Chunk.self, from: data)
        else { return ([], false) }

        switch chunk.type {
        case "content_block_start":
            if chunk.contentBlock?.type == "tool_use", let index = chunk.index {
                toolBlocks[index] = ToolBlock(
                    id: chunk.contentBlock?.id ?? "toolu_\(index)",
                    name: chunk.contentBlock?.name ?? "",
                    json: ""
                )
            }
            return ([], false)

        case "content_block_delta":
            guard let delta = chunk.delta else { return ([], false) }
            if let text = delta.text, !text.isEmpty {
                return ([.text(text)], false)
            }
            if let partial = delta.partialJSON, let index = chunk.index {
                toolBlocks[index]?.json += partial
            }
            return ([], false)

        case "content_block_stop":
            guard let index = chunk.index, let block = toolBlocks.removeValue(forKey: index),
                  !block.name.isEmpty
            else { return ([], false) }
            return ([.toolCall(AIToolCall(id: block.id, name: block.name, arguments: block.json))], false)

        case "message_stop":
            return ([], true)

        default:
            return ([], false)
        }
    }

    private struct Chunk: Decodable {
        let type: String
        let index: Int?
        let contentBlock: ContentBlock?
        let delta: Delta?
        enum CodingKeys: String, CodingKey {
            case type, index, delta
            case contentBlock = "content_block"
        }
        struct ContentBlock: Decodable {
            let type: String
            let id: String?
            let name: String?
        }
        struct Delta: Decodable {
            let text: String?
            let partialJSON: String?
            enum CodingKeys: String, CodingKey {
                case text
                case partialJSON = "partial_json"
            }
        }
    }
}
