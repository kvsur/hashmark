//
//  GeminiRequestBuilder.swift
//  MarkdownApp
//
//  中立消息到 Gemini Interactions input steps、tools 与媒体块的翻译层。
//

import Foundation

nonisolated struct GeminiRequestBuilder {
    private let maxInlineBytes = 20 * 1_024 * 1_024
    let configuration: ResolvedAIProviderConfiguration

    func makeStreamRequest(
        messages: [AIMessage],
        tools: [AITool],
        previousInteractionID: String? = nil,
        uploadedFiles: [GeminiUploadedFile] = [],
        fileSearchStoreNames: [String] = []
    ) throws -> URLRequest {
        let systemInstruction = messages
            .filter { $0.role == .system }
            .map(\.content)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        let input = try inputSteps(messages, uploadedFiles: uploadedFiles)
        let scopedStoreNames = try messages.flatMap(\.providerFiles).compactMap { reference in
            let valid = try reference.validated(for: .gemini)
            return valid.purpose == .retrieval
                ? valid.transportPayload?.string(for: "file_search_store_name")
                : nil
        }
        let allStoreNames = Array(Set(fileSearchStoreNames + scopedStoreNames)).sorted()
        var body: [String: JSONValue] = [
            "model": .string(configuration.model),
            "input": input.count == 1 ? input[0] : .array(input),
            "stream": .bool(true),
            "store": .bool(true)
        ]
        if !systemInstruction.isEmpty { body["system_instruction"] = .string(systemInstruction) }
        if let previousInteractionID {
            body["previous_interaction_id"] = .string(previousInteractionID)
        }
        if configuration.effectiveCapabilities.displayableReasoning.isEnabled {
            body["generation_config"] = .object(["thinking_level": .string("low")])
        }

        var nativeTools = tools.map { tool in
            JSONValue.object([
                "type": .string("function"),
                "name": .string(tool.name),
                "description": .string(tool.description),
                "parameters": tool.parameters
            ])
        }
        if configuration.effectiveCapabilities.webSearch.isEnabled {
            nativeTools.append(.object(["type": .string("google_search")]))
        }
        if !allStoreNames.isEmpty,
           configuration.effectiveCapabilities.fileSearch.isEnabled {
            nativeTools.append(.object([
                "type": .string("file_search"),
                "file_search_store_names": .array(allStoreNames.map(JSONValue.string))
            ]))
        }
        if !nativeTools.isEmpty { body["tools"] = .array(nativeTools) }
        if configuration.effectiveCapabilities.webSearch.isEnabled {
            body["tool_choice"] = .object([
                "allowed_tools": .object([
                    "mode": .string("any"),
                    "tools": .array([.string("google_search")])
                ])
            ])
        }

        var request = URLRequest(url: streamingURL())
        request.httpMethod = "POST"
        request.setValue(configuration.apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("2026-05-20", forHTTPHeaderField: "Api-Revision")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(JSONValue.object(body))
        return request
    }

    private func streamingURL() -> URL {
        var components = URLComponents(url: configuration.endpointURL, resolvingAgainstBaseURL: false)!
        var items = components.queryItems ?? []
        items.removeAll { $0.name == "alt" }
        items.append(URLQueryItem(name: "alt", value: "sse"))
        components.queryItems = items
        return components.url!
    }

    private func inputSteps(
        _ messages: [AIMessage],
        uploadedFiles: [GeminiUploadedFile]
    ) throws -> [JSONValue] {
        let lastUserIndex = messages.lastIndex { $0.role == .user }
        var result: [JSONValue] = []
        for (index, message) in messages.enumerated() where message.role != .system {
            switch message.role {
            case .system:
                continue
            case .user:
                let blocks = try userContent(
                    message,
                    uploadedFiles: index == lastUserIndex ? uploadedFiles : []
                )
                result.append(.object([
                    "type": .string("user_input"),
                    "content": blocks.count == 1 && message.attachments.isEmpty
                        && uploadedFiles.isEmpty && message.providerFiles.isEmpty
                        ? .string(message.content)
                        : .array(blocks)
                ]))
            case .assistant:
                result.append(contentsOf: message.reasoningBlocks.compactMap(interactionStep))
                if !message.content.isEmpty {
                    result.append(.object([
                        "type": .string("model_output"),
                        "content": .array([.object([
                            "type": .string("text"),
                            "text": .string(message.content)
                        ])])
                    ]))
                }
                result.append(contentsOf: message.toolCalls.map { call in
                    .object([
                        "type": .string("function_call"),
                        "id": .string(call.id),
                        "name": .string(call.name),
                        "arguments": parsedJSON(call.arguments)
                    ])
                })
            case .tool:
                result.append(.object([
                    "type": .string("function_result"),
                    "name": .string(message.toolName ?? "tool"),
                    "call_id": .string(message.toolCallId ?? ""),
                    "result": .array([.object([
                        "type": .string("text"),
                        "text": .string(message.content)
                    ])])
                ]))
            }
        }
        return result
    }

    private func userContent(
        _ message: AIMessage,
        uploadedFiles: [GeminiUploadedFile]
    ) throws -> [JSONValue] {
        var content: [JSONValue] = []
        if !message.content.isEmpty {
            content.append(.object(["type": .string("text"), "text": .string(message.content)]))
        }
        for attachment in message.attachments {
            switch attachment.kind {
            case .image(let data):
                guard configuration.effectiveCapabilities.imageInput.isEnabled,
                      !data.isEmpty, data.count <= maxInlineBytes
                else { throw GeminiWireError.unsupportedInput }
                content.append(.object([
                    "type": .string("image"),
                    "data": .string(data.base64EncodedString()),
                    "mime_type": .string("image/jpeg")
                ]))
            case .pdf(let data, _):
                guard configuration.effectiveCapabilities.inlinePDF.isEnabled,
                      !data.isEmpty, data.count <= maxInlineBytes
                else { throw GeminiWireError.unsupportedInput }
                content.append(.object([
                    "type": .string("document"),
                    "data": .string(data.base64EncodedString()),
                    "mime_type": .string("application/pdf")
                ]))
            case .documentReference:
                continue
            }
        }
        for file in uploadedFiles where file.purpose != .retrieval {
            let type = file.mimeType.hasPrefix("image/") ? "image" : "document"
            content.append(.object([
                "type": .string(type),
                "uri": .string(file.uri),
                "mime_type": .string(file.mimeType)
            ]))
        }
        for reference in message.providerFiles {
            let valid = try reference.validated(for: .gemini)
            guard valid.purpose != .retrieval,
                  let uri = valid.transportPayload?.string(for: "uri"),
                  let mimeType = valid.transportPayload?.string(for: "mime_type")
            else { continue }
            content.append(.object([
                "type": .string(mimeType.hasPrefix("image/") ? "image" : "document"),
                "uri": .string(uri),
                "mime_type": .string(mimeType)
            ]))
        }
        return content
    }

    private func interactionStep(_ block: AIReasoningBlock) -> JSONValue? {
        guard let continuation = block.continuation,
              continuation.provider == .gemini,
              continuation.kind == "interaction_step"
        else { return nil }
        return continuation.payload
    }

    private func parsedJSON(_ text: String) -> JSONValue {
        guard let data = text.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data)
        else { return .object([:]) }
        return .foundation(value)
    }
}
