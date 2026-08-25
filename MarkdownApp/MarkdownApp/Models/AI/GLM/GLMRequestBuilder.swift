//
//  GLMRequestBuilder.swift
//  MarkdownApp
//
//  BigModel chat serializer。文本与视觉能力只按 manifest 的精确模型结果分流。
//

import Foundation

nonisolated struct GLMRequestBuilder {
    let configuration: ResolvedAIProviderConfiguration

    func makeStreamRequest(
        messages: [AIMessage],
        tools: [AITool],
        uploadedFiles: [GLMUploadedFile] = [],
        webSearchEvidencePreloaded: Bool = false
    ) throws -> URLRequest {
        guard !configuration.usesNativeWebSearch
                || webSearchEvidencePreloaded
        else { throw GLMWireError.missingWebSearchEvidence }
        let visual = configuration.allowsKnownSafeRequest(.imageInput)
            || configuration.allowsKnownSafeRequest(.pdfInput)
            || configuration.allowsKnownSafeRequest(.genericFileInput)
        let nativeTools = tools.map(functionTool)

        var body: [String: JSONValue] = [
            "model": .string(configuration.model),
            "messages": .array(try serializeMessages(
                messages,
                visual: visual,
                uploadedFiles: uploadedFiles
            )),
            // GLM 的最终 SSE chunk 原生携带 usage；不要发送 OpenAI 的 stream_options。
            "stream": .bool(true)
        ]
        if configuration.supportsKnownSafeRequest(.reasoning) {
            let reasoningStyle = configuration.modelStrategyID(key: "reasoningStyle")
            if reasoningStyle == "glmAlwaysOnReasoning" {
                body["thinking"] = .object(["type": .string("enabled")])
                let effort: String = switch configuration.reasoningEffort {
                case .automatic, .maximum: "max"
                case .low: "low"
                case .high: "high"
                }
                body["reasoning_effort"] = .string(effort)
            } else {
                body["thinking"] = .object([
                    "type": .string("enabled"),
                    "clear_thinking": .bool(false)
                ])
            }
        }
        if !nativeTools.isEmpty {
            body["tools"] = .array(nativeTools)
            body["tool_choice"] = .string("auto")
        }

        var request = URLRequest(url: configuration.endpointURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(JSONValue.object(body))
        return request
    }

    private func serializeMessages(
        _ messages: [AIMessage],
        visual: Bool,
        uploadedFiles: [GLMUploadedFile]
    ) throws -> [JSONValue] {
        let lastUserIndex = messages.lastIndex { $0.role == .user }
        return try messages.enumerated().map { index, message in
            let legacyFiles = index == lastUserIndex ? uploadedFiles : []
            let files = legacyFiles + (try message.providerFiles.map(glmFile))
            return try serializeMessage(message, visual: visual, uploadedFiles: files)
        }
    }

    private func glmFile(_ reference: AIProviderFileReference) throws -> GLMUploadedFile {
        let valid = try reference.validated(for: .glm)
        guard let url = valid.transportPayload?.string(for: "url") else {
            throw GLMWireError.unsupportedInput
        }
        return GLMUploadedFile(
            id: valid.id,
            url: url,
            name: valid.transportPayload?.string(for: "name") ?? valid.id,
            mimeType: valid.transportPayload?.string(for: "mime_type") ?? "application/octet-stream",
            purpose: valid.purpose
        )
    }

    private func serializeMessage(
        _ message: AIMessage,
        visual: Bool,
        uploadedFiles: [GLMUploadedFile]
    ) throws -> JSONValue {
        var object: [String: JSONValue] = ["role": .string(message.role.rawValue)]
        if message.role == .user, !message.attachments.isEmpty || !uploadedFiles.isEmpty {
            guard visual else { throw GLMWireError.unsupportedInput }
            object["content"] = .array(try visualContent(message, uploadedFiles: uploadedFiles))
        } else {
            guard message.attachments.isEmpty else { throw GLMWireError.unsupportedInput }
            object["content"] = .string(message.content)
        }
        if message.role == .assistant {
            let reasoning = reasoningContent(message)
            if !reasoning.isEmpty { object["reasoning_content"] = .string(reasoning) }
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
        if message.role == .tool {
            guard let id = message.toolCallId else { throw GLMWireError.unsupportedInput }
            object["tool_call_id"] = .string(id)
        }
        return .object(object)
    }

    private func visualContent(
        _ message: AIMessage,
        uploadedFiles: [GLMUploadedFile]
    ) throws -> [JSONValue] {
        var mediaKinds: Set<String> = []
        for attachment in message.attachments {
            switch attachment.kind {
            case .image: mediaKinds.insert("image")
            case .pdf: mediaKinds.insert("file")
            case .documentReference: break
            }
        }
        for file in uploadedFiles {
            mediaKinds.insert(file.mimeType.hasPrefix("image/") ? "image" : "file")
        }
        // GLM-5V 官方契约不允许同一请求混用 image/video/file 模态。
        guard mediaKinds.count <= 1 else { throw GLMWireError.unsupportedInput }

        var content: [JSONValue] = []
        if !message.content.isEmpty {
            content.append(.object(["type": .string("text"), "text": .string(message.content)]))
        }
        for attachment in message.attachments {
            switch attachment.kind {
            case .image(let data):
                guard configuration.allowsKnownSafeRequest(.imageInput), !data.isEmpty else {
                    throw GLMWireError.unsupportedInput
                }
                content.append(mediaBlock(
                    type: "image_url",
                    key: "image_url",
                    url: data.base64EncodedString()
                ))
            case .pdf(let data, _):
                guard configuration.allowsKnownSafeRequest(.pdfInput), !data.isEmpty else {
                    throw GLMWireError.unsupportedInput
                }
                content.append(mediaBlock(
                    type: "file_url",
                    key: "file_url",
                    url: "data:application/pdf;base64,\(data.base64EncodedString())"
                ))
            case .documentReference:
                continue
            }
        }
        for file in uploadedFiles {
            let capability: AIModelCapability = file.mimeType.hasPrefix("image/")
                ? .imageInput
                : .genericFileInput
            guard configuration.allowsKnownSafeRequest(capability) else {
                throw GLMWireError.unsupportedInput
            }
            let type = file.mimeType.hasPrefix("image/") ? "image_url" : "file_url"
            content.append(mediaBlock(type: type, key: type, url: file.url))
        }
        return content
    }

    private func mediaBlock(type: String, key: String, url: String) -> JSONValue {
        .object([
            "type": .string(type),
            key: .object(["url": .string(url)])
        ])
    }

    private func reasoningContent(_ message: AIMessage) -> String {
        let privateValues = message.reasoningBlocks.compactMap { block -> String? in
            guard block.continuation?.provider == .glm,
                  block.continuation?.kind == "reasoning_content",
                  case .string(let value)? = block.continuation?.payload else { return nil }
            return value
        }
        return privateValues.isEmpty
            ? message.reasoningBlocks.map(\.visibleText).joined()
            : privateValues.joined()
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
