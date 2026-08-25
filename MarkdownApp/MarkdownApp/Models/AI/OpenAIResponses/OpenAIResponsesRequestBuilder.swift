//
//  OpenAIResponsesRequestBuilder.swift
//  MarkdownApp
//
//  将 App-domain message/tool/attachment 精确翻译为 Responses input items。
//

import Foundation

nonisolated struct OpenAIResponsesRequestBuilder {
    let configuration: ResolvedAIProviderConfiguration

    func makeStreamRequest(
        messages: [AIMessage],
        instructions: String?,
        tools: [AITool],
        previousResponseID: String?,
        uploadedFileIDs: [String] = [],
        vectorStoreIDs: [String] = []
    ) throws -> URLRequest {
        guard previousResponseID == nil || !messages.isEmpty else {
            throw OpenAIResponsesWireError.emptyContinuation
        }

        let input = try inputItems(messages: messages, uploadedFileIDs: uploadedFileIDs)
        let scopedStoreIDs = try messages.flatMap(\.providerFiles).compactMap { reference in
            let valid = try reference.validated(for: .openAI)
            return valid.purpose == .retrieval
                ? valid.transportPayload?.string(for: "vector_store_id")
                : nil
        }
        let allVectorStoreIDs = Array(Set(vectorStoreIDs + scopedStoreIDs)).sorted()
        var body: [String: JSONValue] = [
            "model": .string(configuration.model),
            "stream": .bool(true),
            "store": .bool(true),
            "input": .array(input),
            "parallel_tool_calls": .bool(false)
        ]

        if let instructions, !instructions.isEmpty {
            body["instructions"] = .string(instructions)
        }
        if let previousResponseID {
            body["previous_response_id"] = .string(previousResponseID)
        }

        let nativeTools = requestTools(appTools: tools, vectorStoreIDs: allVectorStoreIDs)
        if !nativeTools.isEmpty {
            body["tools"] = .array(nativeTools)
            if configuration.effectiveCapabilities.webSearch.isEnabled,
               case .openAIHostedTool(let type) = configuration.manifest.webSearch {
                body["tool_choice"] = .object([
                    "type": .string("allowed_tools"),
                    "mode": .string("required"),
                    "tools": .array([.object(["type": .string(type)])])
                ])
            } else {
                body["tool_choice"] = .string("auto")
            }
        }

        var include: [JSONValue] = []
        if configuration.effectiveCapabilities.webSearch.isEnabled {
            include.append(.string("web_search_call.action.sources"))
        }
        if !allVectorStoreIDs.isEmpty, configuration.effectiveCapabilities.fileSearch.isEnabled {
            include.append(.string("file_search_call.results"))
        }
        if !include.isEmpty { body["include"] = .array(include) }

        if configuration.effectiveCapabilities.displayableReasoning.isEnabled {
            body["reasoning"] = .object(["generate_summary": .string("auto")])
        }

        var request = URLRequest(url: configuration.endpointURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(JSONValue.object(body))
        return request
    }

    private func inputItems(
        messages: [AIMessage],
        uploadedFileIDs: [String]
    ) throws -> [JSONValue] {
        let lastUserIndex = messages.lastIndex { $0.role == .user }
        var items: [JSONValue] = []

        for (index, message) in messages.enumerated() {
            switch message.role {
            case .system:
                continue
            case .tool:
                guard let callID = message.toolCallId else { continue }
                items.append(.object([
                    "type": .string("function_call_output"),
                    "call_id": .string(callID),
                    "output": .string(message.content)
                ]))
            case .user, .assistant:
                let extraFileIDs = index == lastUserIndex ? uploadedFileIDs : []
                if let item = try messageItem(message, uploadedFileIDs: extraFileIDs) {
                    items.append(item)
                }
                if message.role == .assistant {
                    items.append(contentsOf: message.toolCalls.map { call in
                        .object([
                            "type": .string("function_call"),
                            "call_id": .string(call.id),
                            "name": .string(call.name),
                            "arguments": .string(call.arguments)
                        ])
                    })
                }
            }
        }
        return items
    }

    private func messageItem(
        _ message: AIMessage,
        uploadedFileIDs: [String]
    ) throws -> JSONValue? {
        let scopedFileIDs = try message.providerFiles.compactMap { reference in
            let valid = try reference.validated(for: .openAI)
            return valid.purpose == .retrieval ? nil : valid.id
        }
        let allFileIDs = uploadedFileIDs + scopedFileIDs
        let hasAttachments = !message.attachments.isEmpty || !allFileIDs.isEmpty
        if !hasAttachments {
            guard !message.content.isEmpty else { return nil }
            return .object([
                "role": .string(message.role.rawValue),
                "content": .string(message.content)
            ])
        }

        var content: [JSONValue] = []
        if !message.content.isEmpty {
            content.append(.object([
                "type": .string("input_text"),
                "text": .string(message.content)
            ]))
        }

        for attachment in message.attachments {
            switch attachment.kind {
            case .image(let data):
                guard configuration.effectiveCapabilities.imageInput.isEnabled else {
                    throw OpenAIResponsesWireError.unsupportedInput
                }
                content.append(.object([
                    "type": .string("input_image"),
                    "image_url": .string("data:image/jpeg;base64,\(data.base64EncodedString())"),
                    "detail": .string("auto")
                ]))
            case .pdf(let data, let name):
                guard configuration.effectiveCapabilities.inlinePDF.isEnabled else {
                    throw OpenAIResponsesWireError.unsupportedInput
                }
                content.append(.object([
                    "type": .string("input_file"),
                    "filename": .string(name),
                    "file_data": .string("data:application/pdf;base64,\(data.base64EncodedString())")
                ]))
            case .documentReference:
                // AIAction 已将文档正文拼入 message.content，不能在这里重复发送。
                continue
            }
        }

        for fileID in allFileIDs {
            content.append(.object([
                "type": .string("input_file"),
                "file_id": .string(fileID)
            ]))
        }

        guard !content.isEmpty else { return nil }
        return .object([
            "role": .string(message.role.rawValue),
            "content": .array(content)
        ])
    }

    private func requestTools(
        appTools: [AITool],
        vectorStoreIDs: [String]
    ) -> [JSONValue] {
        var result = appTools.map { tool in
            JSONValue.object([
                "type": .string("function"),
                "name": .string(tool.name),
                "description": .string(tool.description),
                "parameters": tool.parameters,
                "strict": .bool(false)
            ])
        }

        if configuration.effectiveCapabilities.webSearch.isEnabled,
           case .openAIHostedTool(let type) = configuration.manifest.webSearch {
            result.append(.object(["type": .string(type)]))
        }

        if !vectorStoreIDs.isEmpty, configuration.effectiveCapabilities.fileSearch.isEnabled {
            result.append(.object([
                "type": .string("file_search"),
                "vector_store_ids": .array(vectorStoreIDs.map(JSONValue.string)),
                "max_num_results": .number(20)
            ]))
        }
        return result
    }
}
