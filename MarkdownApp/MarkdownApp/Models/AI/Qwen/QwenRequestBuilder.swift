//
//  QwenRequestBuilder.swift
//  MarkdownApp
//
//  DashScope native input/parameters serializer。多模态模型必须切换独立 endpoint。
//

import Foundation

nonisolated struct QwenRequestBuilder {
    let configuration: ResolvedAIProviderConfiguration

    func makeStreamRequest(
        messages: [AIMessage],
        tools: [AITool],
        uploadedFiles: [QwenUploadedFile] = []
    ) throws -> URLRequest {
        let route = QwenModelContract.route(for: configuration.model)
        let multimodal = route == .multimodal
        let nativeMessages = try serializeMessages(
            messages,
            multimodal: multimodal,
            uploadedFiles: uploadedFiles
        )
        var parameters: [String: JSONValue] = [
            "result_format": .string("message"),
            "incremental_output": .bool(true)
        ]
        if configuration.effectiveCapabilities.displayableReasoning.isEnabled {
            parameters["enable_thinking"] = .bool(true)
        }
        if configuration.effectiveCapabilities.webSearch.isEnabled {
            parameters["enable_search"] = .bool(true)
            var searchOptions: [String: JSONValue] = [
                "enable_source": .bool(true),
                "forced_search": .bool(true)
            ]
            if QwenModelContract.searchOptionsStyle(for: configuration.model) == .multimodalAgent {
                // DashScope agent strategy only accepts source return; citation options are invalid here.
                searchOptions["search_strategy"] = .string("agent")
            } else {
                searchOptions["enable_citation"] = .bool(true)
                searchOptions["citation_format"] = .string("[ref_<number>]")
            }
            parameters["search_options"] = .object(searchOptions)
        }
        if !tools.isEmpty {
            parameters["tools"] = .array(tools.map { tool in
                .object([
                    "type": .string("function"),
                    "function": .object([
                        "name": .string(tool.name),
                        "description": .string(tool.description),
                        "parameters": tool.parameters
                    ])
                ])
            })
            parameters["tool_choice"] = .string("auto")
        }

        let body: JSONValue = .object([
            "model": .string(configuration.model),
            "input": .object(["messages": .array(nativeMessages)]),
            "parameters": .object(parameters)
        ])
        var request = URLRequest(url: try endpoint(route: route))
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("enable", forHTTPHeaderField: "X-DashScope-SSE")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func endpoint(route: QwenNativeRoute) throws -> URL {
        let textPath = "/services/aigc/text-generation/generation"
        let multimodalPath = "/services/aigc/multimodal-generation/generation"
        var components = URLComponents(
            url: configuration.endpointURL,
            resolvingAgainstBaseURL: false
        )!
        guard !components.path.contains("/compatible-mode/") else {
            throw QwenWireError.invalidNativeRoute
        }
        if route == .multimodal {
            guard components.path.hasSuffix(textPath) || components.path.hasSuffix(multimodalPath) else {
                throw QwenWireError.invalidNativeRoute
            }
            components.path = components.path.replacingOccurrences(of: textPath, with: multimodalPath)
        }
        guard let url = components.url else { throw QwenWireError.invalidNativeRoute }
        return url
    }

    private func serializeMessages(
        _ messages: [AIMessage],
        multimodal: Bool,
        uploadedFiles: [QwenUploadedFile]
    ) throws -> [JSONValue] {
        let lastUserIndex = messages.lastIndex { $0.role == .user }
        return try messages.enumerated().map { index, message in
            let legacyFiles = index == lastUserIndex ? uploadedFiles : []
            let files = legacyFiles + (try message.providerFiles.map(qwenFile))
            if multimodal {
                return try multimodalMessage(message, uploadedFiles: files)
            }
            return try textMessage(message, uploadedFiles: files)
        }
    }

    private func qwenFile(_ reference: AIProviderFileReference) throws -> QwenUploadedFile {
        let valid = try reference.validated(for: .qwen)
        return QwenUploadedFile(
            id: valid.id,
            name: valid.transportPayload?.string(for: "name") ?? valid.id,
            mimeType: valid.transportPayload?.string(for: "mime_type") ?? "application/octet-stream",
            purpose: valid.purpose,
            extractedText: valid.transportPayload?.string(for: "extracted_text")
        )
    }

    private func textMessage(
        _ message: AIMessage,
        uploadedFiles: [QwenUploadedFile]
    ) throws -> JSONValue {
        guard message.attachments.allSatisfy({ attachment in
            if case .documentReference = attachment.kind { return true }
            return false
        }) else { throw QwenWireError.unsupportedInput }
        var object: [String: JSONValue] = ["role": .string(message.role.rawValue)]
        let extracted = uploadedFiles.compactMap(\.extractedText)
        object["content"] = .string(([message.content] + extracted).filter { !$0.isEmpty }
            .joined(separator: "\n\n"))
        addAssistantFields(message, to: &object)
        if message.role == .tool, let id = message.toolCallId {
            object["tool_call_id"] = .string(id)
        }
        return .object(object)
    }

    private func multimodalMessage(
        _ message: AIMessage,
        uploadedFiles: [QwenUploadedFile]
    ) throws -> JSONValue {
        var object: [String: JSONValue] = ["role": .string(message.role.rawValue)]
        var content: [JSONValue] = []
        if !message.content.isEmpty { content.append(.object(["text": .string(message.content)])) }
        for attachment in message.attachments {
            switch attachment.kind {
            case .image(let data):
                guard !data.isEmpty else { throw QwenWireError.unsupportedInput }
                content.append(.object([
                    "image": .string("data:image/jpeg;base64,\(data.base64EncodedString())")
                ]))
            case .pdf(let data, _):
                guard configuration.effectiveCapabilities.inlinePDF.isEnabled, !data.isEmpty else {
                    throw QwenWireError.unsupportedInput
                }
                content.append(.object([
                    "file": .string("data:application/pdf;base64,\(data.base64EncodedString())")
                ]))
            case .documentReference:
                continue
            }
        }
        for file in uploadedFiles {
            if let text = file.extractedText {
                content.append(.object(["text": .string(text)]))
            } else if file.mimeType.hasPrefix("image/") {
                content.append(.object(["image": .string("file://\(file.id)")]))
            } else {
                content.append(.object(["file": .string("file://\(file.id)")]))
            }
        }
        object["content"] = .array(content)
        addAssistantFields(message, to: &object)
        if message.role == .tool, let id = message.toolCallId {
            object["tool_call_id"] = .string(id)
        }
        return .object(object)
    }

    private func addAssistantFields(_ message: AIMessage, to object: inout [String: JSONValue]) {
        guard message.role == .assistant else { return }
        if let reasoning = message.reasoningBlocks.first?.visibleText, !reasoning.isEmpty {
            object["reasoning_content"] = .string(reasoning)
        }
        if !message.toolCalls.isEmpty {
            object["tool_calls"] = .array(message.toolCalls.enumerated().map { index, call in
                .object([
                    "index": .number(Double(index)),
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
}
