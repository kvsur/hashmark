//
//  AnthropicRequestBuilder.swift
//  MarkdownApp
//
//  App-domain 消息到 Anthropic Messages content blocks 的唯一翻译层。
//

import Foundation

nonisolated struct AnthropicRequestBuilder {
    private let maxTokens = 8_192
    private let maxInlineImageBytes = 5 * 1_024 * 1_024
    private let maxRequestPDFBytes = 32 * 1_024 * 1_024

    let configuration: ResolvedAIProviderConfiguration

    func makeStreamRequest(
        messages: [AIMessage],
        tools: [AITool],
        uploadedFiles: [AnthropicUploadedFile] = []
    ) throws -> URLRequest {
        let system = messages
            .filter { $0.role == .system }
            .map(\.content)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        let lastUserIndex = messages.lastIndex { $0.role == .user }
        let turns = try messages.enumerated().compactMap { index, message -> JSONValue? in
            guard message.role != .system else { return nil }
            return try serialize(
                message,
                uploadedFiles: index == lastUserIndex ? uploadedFiles : []
            )
        }

        var body: [String: JSONValue] = [
            "model": .string(configuration.model),
            "max_tokens": .number(Double(maxTokens)),
            "messages": .array(turns),
            "stream": .bool(true)
        ]
        if !system.isEmpty { body["system"] = .string(system) }

        var nativeTools = tools.map { tool in
            JSONValue.object([
                "name": .string(tool.name),
                "description": .string(tool.description),
                "input_schema": tool.parameters
            ])
        }
        if configuration.effectiveCapabilities.webSearch.isEnabled {
            guard case .anthropicServerTool(let version) = configuration.manifest.webSearch,
                  version == "web_search_20260318"
            else { throw AnthropicWireError.invalidToolVersion }
            nativeTools.append(.object([
                "type": .string(version),
                "name": .string("web_search"),
                "max_uses": .number(5),
                "response_inclusion": .string("full")
            ]))
        }
        if !nativeTools.isEmpty { body["tools"] = .array(nativeTools) }
        if configuration.effectiveCapabilities.webSearch.isEnabled {
            body["tool_choice"] = .object([
                "type": .string("tool"),
                "name": .string("web_search"),
                "disable_parallel_tool_use": .bool(true)
            ])
        }

        if configuration.effectiveCapabilities.displayableReasoning.isEnabled {
            body["thinking"] = thinkingConfiguration()
        }

        var request = URLRequest(url: configuration.endpointURL)
        request.httpMethod = "POST"
        request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if !uploadedFiles.isEmpty || messages.contains(where: { !$0.providerFiles.isEmpty }) {
            request.setValue("files-api-2025-04-14", forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try JSONEncoder().encode(JSONValue.object(body))
        return request
    }

    private var apiVersion: String {
        guard case .anthropic(let version) = configuration.manifest.authentication else {
            return "2023-06-01"
        }
        return version
    }

    private func thinkingConfiguration() -> JSONValue {
        let adaptiveModels: Set<String> = [
            "claude-fable-5", "claude-mythos-5", "claude-opus-4-8",
            "claude-opus-4-7", "claude-sonnet-5"
        ]
        if adaptiveModels.contains(configuration.model.lowercased()) {
            return .object([
                "type": .string("adaptive"),
                "display": .string("summarized")
            ])
        }
        return .object([
            "type": .string("enabled"),
            "budget_tokens": .number(1_024),
            "display": .string("summarized")
        ])
    }

    private func serialize(
        _ message: AIMessage,
        uploadedFiles: [AnthropicUploadedFile]
    ) throws -> JSONValue {
        switch message.role {
        case .system:
            return .object(["role": .string("user"), "content": .string(message.content)])
        case .user:
            let blocks = try userBlocks(message, uploadedFiles: uploadedFiles)
            return .object([
                "role": .string("user"),
                "content": blocks.count == 1 && message.attachments.isEmpty
                    && uploadedFiles.isEmpty && message.providerFiles.isEmpty
                    ? .string(message.content)
                    : .array(blocks)
            ])
        case .assistant:
            var blocks = message.reasoningBlocks.compactMap(reasoningBlock)
            if !message.content.isEmpty {
                blocks.append(.object(["type": .string("text"), "text": .string(message.content)]))
            }
            blocks.append(contentsOf: message.toolCalls.map { call in
                .object([
                    "type": .string("tool_use"),
                    "id": .string(call.id),
                    "name": .string(call.name),
                    "input": parsedObject(call.arguments)
                ])
            })
            return .object(["role": .string("assistant"), "content": .array(blocks)])
        case .tool:
            return .object([
                "role": .string("user"),
                "content": .array([.object([
                    "type": .string("tool_result"),
                    "tool_use_id": .string(message.toolCallId ?? ""),
                    "content": .string(message.content)
                ])])
            ])
        }
    }

    private func userBlocks(
        _ message: AIMessage,
        uploadedFiles: [AnthropicUploadedFile]
    ) throws -> [JSONValue] {
        var blocks: [JSONValue] = []
        if !message.content.isEmpty {
            blocks.append(.object(["type": .string("text"), "text": .string(message.content)]))
        }
        for attachment in message.attachments {
            switch attachment.kind {
            case .image(let data):
                guard configuration.effectiveCapabilities.imageInput.isEnabled,
                      !data.isEmpty, data.count <= maxInlineImageBytes
                else { throw AnthropicWireError.unsupportedInput }
                blocks.append(.object([
                    "type": .string("image"),
                    "source": .object([
                        "type": .string("base64"),
                        "media_type": .string("image/jpeg"),
                        "data": .string(data.base64EncodedString())
                    ])
                ]))
            case .pdf(let data, let name):
                guard configuration.effectiveCapabilities.inlinePDF.isEnabled,
                      !data.isEmpty, data.count <= maxRequestPDFBytes
                else { throw AnthropicWireError.unsupportedInput }
                blocks.append(.object([
                    "type": .string("document"),
                    "title": .string(name),
                    "source": .object([
                        "type": .string("base64"),
                        "media_type": .string("application/pdf"),
                        "data": .string(data.base64EncodedString())
                    ])
                ]))
            case .documentReference:
                continue
            }
        }
        for file in uploadedFiles {
            let type = file.mimeType.hasPrefix("image/") ? "image" : "document"
            blocks.append(.object([
                "type": .string(type),
                "source": .object([
                    "type": .string("file"),
                    "file_id": .string(file.id)
                ])
            ]))
        }
        for reference in message.providerFiles {
            let valid = try reference.validated(for: .anthropic)
            let mimeType = valid.transportPayload?.string(for: "mime_type") ?? "application/octet-stream"
            blocks.append(.object([
                "type": .string(mimeType.hasPrefix("image/") ? "image" : "document"),
                "source": .object([
                    "type": .string("file"),
                    "file_id": .string(valid.id)
                ])
            ]))
        }
        return blocks
    }

    private func reasoningBlock(_ block: AIReasoningBlock) -> JSONValue? {
        guard let continuation = block.continuation,
              continuation.provider == .anthropic,
              continuation.kind == "thinking_block"
        else { return nil }
        return continuation.payload
    }

    private func parsedObject(_ text: String) -> JSONValue {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .object([:]) }
        return .foundation(object)
    }
}
