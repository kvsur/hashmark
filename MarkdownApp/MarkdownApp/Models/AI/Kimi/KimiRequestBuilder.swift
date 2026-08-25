//
//  KimiRequestBuilder.swift
//  MarkdownApp
//
//  Kimi chat serializer：K2 thinking 与 K3 reasoning_effort 的差异只在此处实现。
//

import Foundation

nonisolated struct KimiRequestBuilder {
    let configuration: ResolvedAIProviderConfiguration

    func makeStreamRequest(
        messages: [AIMessage],
        tools: [AITool],
        uploadedFiles: [KimiUploadedFile] = [],
        formulaTools: [JSONValue] = [],
        webSearchPolicy: String? = nil
    ) throws -> URLRequest {
        let webSearch = configuration.usesNativeWebSearch
        let reasoningStyle = configuration.modelStrategyID(key: "reasoningStyle")
        let requestMessages: [AIMessage]
        if webSearch {
            guard let webSearchPolicy, !webSearchPolicy.isEmpty else {
                throw KimiWireError.missingWebSearchPolicy
            }
            requestMessages = Self.injectingWebSearchPolicy(
                webSearchPolicy,
                into: messages
            )
        } else {
            requestMessages = messages
        }
        var nativeTools = tools.map(functionTool)
        if webSearch {
            guard formulaTools.contains(where: Self.isWebSearchFormulaTool) else {
                throw KimiWireError.missingFormulaTool
            }
            nativeTools.append(contentsOf: formulaTools)
        }

        var body: [String: JSONValue] = [
            "model": .string(configuration.model),
            "messages": .array(try serializeMessages(
                requestMessages,
                uploadedFiles: uploadedFiles
            )),
            "stream": .bool(true),
            "stream_options": .object(["include_usage": .bool(true)]),
            "max_completion_tokens": .number(32_768)
        ]
        if configuration.allowsKnownSafeRequest(.reasoning),
           reasoningStyle == "kimiReasoningEffort" {
            let effort: String = switch configuration.reasoningEffort {
            case .automatic, .maximum: "max"
            case .low: "low"
            case .high: "high"
            }
            body["reasoning_effort"] = .string(effort)
        } else if webSearch {
            body["thinking"] = .object(["type": .string("disabled")])
        } else if configuration.allowsKnownSafeRequest(.reasoning),
                  reasoningStyle == "kimiThinkingToggle" {
            body["thinking"] = .object(["type": .string("enabled")])
        }
        if !nativeTools.isEmpty {
            body["tools"] = .array(nativeTools)
            // Kimi K2.6 仅支持 auto/none，不支持 OpenAI 的 required。生产路径会先由
            // Adapter 确定性执行 Formula，再以 none 合成答案，避免再次搜索。
            body["tool_choice"] = .string(
                webSearch && Self.hasWebSearchResultForLatestUserTurn(in: messages)
                    ? "none"
                    : "auto"
            )
        }

        var request = URLRequest(url: configuration.endpointURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(JSONValue.object(body))
        return request
    }

    /// Web Search 开启时，每个尚无搜索结果的新用户回合都由 Adapter 先执行 Formula。
    /// 查询就是用户本轮原文，不再维护脆弱的关键词/语言表。
    func pendingWebSearchQuery(in messages: [AIMessage]) -> String? {
        guard configuration.usesNativeWebSearch,
              let userIndex = messages.lastIndex(where: { $0.role == .user }),
              !Self.hasWebSearchResult(after: userIndex, in: messages)
        else { return nil }
        let query = messages[userIndex].content.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? nil : query
    }

    private static func injectingWebSearchPolicy(
        _ webSearchPolicy: String,
        into messages: [AIMessage]
    ) -> [AIMessage] {
        let history = messages.filter { message in
            !(message.role == .system && message.content == webSearchPolicy)
        }
        return [AIMessage(role: .system, content: webSearchPolicy)] + history
    }

    private static func hasWebSearchResultForLatestUserTurn(in messages: [AIMessage]) -> Bool {
        guard let userIndex = messages.lastIndex(where: { $0.role == .user }) else { return false }
        return hasWebSearchResult(after: userIndex, in: messages)
    }

    private static func hasWebSearchResult(after userIndex: Int, in messages: [AIMessage]) -> Bool {
        messages.dropFirst(userIndex + 1).contains {
            $0.role == .tool && $0.toolName == KimiFormulaContract.webSearchToolName
        }
    }

    private static func isWebSearchFormulaTool(_ value: JSONValue) -> Bool {
        guard case .object(let tool) = value,
              case .string("function")? = tool["type"],
              case .object(let function)? = tool["function"],
              case .string(let name)? = function["name"]
        else { return false }
        return name == KimiFormulaContract.webSearchToolName
    }

    private func serializeMessages(
        _ messages: [AIMessage],
        uploadedFiles: [KimiUploadedFile]
    ) throws -> [JSONValue] {
        let lastUserIndex = messages.lastIndex { $0.role == .user }
        return try messages.enumerated().map { index, message in
            let legacyFiles = index == lastUserIndex ? uploadedFiles : []
            return try serializeMessage(
                message,
                uploadedFiles: legacyFiles + (try message.providerFiles.map(kimiFile))
            )
        }
    }

    private func kimiFile(_ reference: AIProviderFileReference) throws -> KimiUploadedFile {
        let valid = try reference.validated(for: .kimi)
        return KimiUploadedFile(
            id: valid.id,
            name: valid.transportPayload?.string(for: "name") ?? valid.id,
            mimeType: valid.transportPayload?.string(for: "mime_type") ?? "application/octet-stream",
            purpose: valid.purpose,
            extractedText: valid.transportPayload?.string(for: "extracted_text")
        )
    }

    private func serializeMessage(
        _ message: AIMessage,
        uploadedFiles: [KimiUploadedFile]
    ) throws -> JSONValue {
        var object: [String: JSONValue] = ["role": .string(message.role.rawValue)]
        if message.role == .user, !message.attachments.isEmpty || !uploadedFiles.isEmpty {
            object["content"] = .array(try userContent(message, uploadedFiles: uploadedFiles))
        } else {
            guard message.attachments.isEmpty else { throw KimiWireError.unsupportedInput }
            object["content"] = .string(message.content)
        }

        if message.role == .assistant {
            if let reasoning = reasoningContent(message), !reasoning.isEmpty {
                object["reasoning_content"] = .string(reasoning)
            }
            if !message.toolCalls.isEmpty {
                object["tool_calls"] = .array(message.toolCalls.map { call in
                    .object([
                        "id": .string(call.id),
                        "type": .string("function"),
                        "function": .object([
                            "name": .string(call.name),
                            "arguments": .string(call.arguments)
                        ])
                    ])
                })
            }
        }
        if message.role == .tool {
            guard let id = message.toolCallId else { throw KimiWireError.unsupportedInput }
            object["tool_call_id"] = .string(id)
        }
        return .object(object)
    }

    private func userContent(
        _ message: AIMessage,
        uploadedFiles: [KimiUploadedFile]
    ) throws -> [JSONValue] {
        var content: [JSONValue] = []
        if !message.content.isEmpty {
            content.append(.object(["type": .string("text"), "text": .string(message.content)]))
        }
        for attachment in message.attachments {
            switch attachment.kind {
            case .image(let data):
                guard configuration.allowsKnownSafeRequest(.imageInput), !data.isEmpty else {
                    throw KimiWireError.unsupportedInput
                }
                content.append(mediaURL(
                    type: "image_url",
                    value: "data:image/jpeg;base64,\(data.base64EncodedString())"
                ))
            case .pdf:
                // Kimi 的普通文档走 Files/extract；不把 PDF 伪装成视觉媒体。
                throw KimiWireError.unsupportedInput
            case .documentReference:
                continue
            }
        }
        for file in uploadedFiles {
            if let text = file.extractedText {
                content.append(.object(["type": .string("text"), "text": .string(text)]))
            } else if file.mimeType.hasPrefix("image/") {
                content.append(mediaURL(type: "image_url", value: "ms://\(file.id)"))
            } else if file.mimeType.hasPrefix("video/") {
                content.append(mediaURL(type: "video_url", value: "ms://\(file.id)"))
            } else {
                throw KimiWireError.unsupportedInput
            }
        }
        return content
    }

    private func mediaURL(type: String, value: String) -> JSONValue {
        .object([
            "type": .string(type),
            type: .object(["url": .string(value)])
        ])
    }

    private func reasoningContent(_ message: AIMessage) -> String? {
        let continuations = message.reasoningBlocks.compactMap { block -> String? in
            guard block.continuation?.provider == .kimi,
                  block.continuation?.kind == "reasoning_content",
                  case .string(let value)? = block.continuation?.payload else { return nil }
            return value
        }
        if !continuations.isEmpty { return continuations.joined() }
        let visible = message.reasoningBlocks.map(\.visibleText).joined()
        return visible.isEmpty ? nil : visible
    }

    private func functionTool(_ tool: AITool) -> JSONValue {
        .object([
            "type": .string("function"),
            "function": .object([
                "name": .string(tool.name),
                "description": .string(tool.description),
                "parameters": tool.parameters
            ])
        ])
    }
}
