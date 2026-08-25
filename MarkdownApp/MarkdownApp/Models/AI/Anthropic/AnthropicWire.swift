//
//  AnthropicWire.swift
//  MarkdownApp
//
//  Anthropic Messages 专属 wire 类型。任何签名、redacted thinking 或搜索结果块
//  都只在 Anthropic 模块内解释，并以 opaque continuation 交给中立层。
//

import Foundation

nonisolated enum AnthropicWireError: Error, Equatable {
    case invalidEvent
    case remote(type: String?, message: String)
    case unsupportedInput
    case invalidToolVersion
}

nonisolated struct AnthropicUploadedFile: Equatable {
    let id: String
    let mimeType: String
    let purpose: AIFilePurpose
}

nonisolated struct AnthropicWireUsage: Decodable, Equatable {
    let inputTokens: Int?
    let outputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

nonisolated struct AnthropicWireErrorPayload: Decodable, Equatable {
    let type: String?
    let message: String?
}

nonisolated struct AnthropicWireCitation: Decodable, Equatable {
    let type: String?
    let url: String?
    let title: String?
    let citedText: String?
    let encryptedIndex: String?

    enum CodingKeys: String, CodingKey {
        case type, url, title
        case citedText = "cited_text"
        case encryptedIndex = "encrypted_index"
    }
}

nonisolated struct AnthropicWireContentBlock: Decodable, Equatable {
    let type: String
    let id: String?
    let name: String?
    let text: String?
    let thinking: String?
    let signature: String?
    let data: String?
    let input: JSONValue?
    let content: JSONValue?
    let citations: [AnthropicWireCitation]?
    let toolUseID: String?

    enum CodingKeys: String, CodingKey {
        case type, id, name, text, thinking, signature, data, input, content, citations
        case toolUseID = "tool_use_id"
    }
}

nonisolated struct AnthropicWireMessage: Decodable, Equatable {
    let id: String?
    let stopReason: String?
    let usage: AnthropicWireUsage?
    let content: [AnthropicWireContentBlock]?

    enum CodingKeys: String, CodingKey {
        case id, usage, content
        case stopReason = "stop_reason"
    }
}

private nonisolated struct AnthropicWireDelta: Decodable {
    let type: String?
    let text: String?
    let thinking: String?
    let signature: String?
    let partialJSON: String?
    let stopReason: String?
    let citation: AnthropicWireCitation?

    enum CodingKeys: String, CodingKey {
        case type, text, thinking, signature, citation
        case partialJSON = "partial_json"
        case stopReason = "stop_reason"
    }
}

private nonisolated struct AnthropicWireEnvelope: Decodable {
    let type: String
    let index: Int?
    let contentBlock: AnthropicWireContentBlock?
    let delta: AnthropicWireDelta?
    let message: AnthropicWireMessage?
    let usage: AnthropicWireUsage?
    let error: AnthropicWireErrorPayload?

    enum CodingKeys: String, CodingKey {
        case type, index, delta, message, usage, error
        case contentBlock = "content_block"
    }
}

nonisolated enum AnthropicWireEvent: Equatable {
    case messageStart(AnthropicWireMessage)
    case blockStart(index: Int, block: AnthropicWireContentBlock)
    case textDelta(index: Int, text: String)
    case thinkingDelta(index: Int, text: String)
    case signatureDelta(index: Int, signature: String)
    case inputJSONDelta(index: Int, fragment: String)
    case citationDelta(index: Int, citation: AnthropicWireCitation)
    case blockStop(index: Int)
    case messageDelta(stopReason: String?, usage: AnthropicWireUsage?)
    case messageStop
    case ping

    init(data: Data, decoder: JSONDecoder = JSONDecoder()) throws {
        let envelope: AnthropicWireEnvelope
        do {
            envelope = try decoder.decode(AnthropicWireEnvelope.self, from: data)
        } catch {
            throw AnthropicWireError.invalidEvent
        }

        switch envelope.type {
        case "message_start":
            guard let message = envelope.message else { throw AnthropicWireError.invalidEvent }
            self = .messageStart(message)
        case "content_block_start":
            guard let index = envelope.index, let block = envelope.contentBlock else {
                throw AnthropicWireError.invalidEvent
            }
            self = .blockStart(index: index, block: block)
        case "content_block_delta":
            guard let index = envelope.index, let delta = envelope.delta else {
                throw AnthropicWireError.invalidEvent
            }
            switch delta.type {
            case "text_delta":
                guard let text = delta.text else { throw AnthropicWireError.invalidEvent }
                self = .textDelta(index: index, text: text)
            case "thinking_delta":
                guard let text = delta.thinking else { throw AnthropicWireError.invalidEvent }
                self = .thinkingDelta(index: index, text: text)
            case "signature_delta":
                guard let signature = delta.signature else { throw AnthropicWireError.invalidEvent }
                self = .signatureDelta(index: index, signature: signature)
            case "input_json_delta":
                guard let fragment = delta.partialJSON else { throw AnthropicWireError.invalidEvent }
                self = .inputJSONDelta(index: index, fragment: fragment)
            case "citations_delta":
                guard let citation = delta.citation else { throw AnthropicWireError.invalidEvent }
                self = .citationDelta(index: index, citation: citation)
            default:
                throw AnthropicWireError.invalidEvent
            }
        case "content_block_stop":
            guard let index = envelope.index else { throw AnthropicWireError.invalidEvent }
            self = .blockStop(index: index)
        case "message_delta":
            self = .messageDelta(
                stopReason: envelope.delta?.stopReason,
                usage: envelope.usage
            )
        case "message_stop":
            self = .messageStop
        case "ping":
            self = .ping
        case "error":
            throw AnthropicWireError.remote(
                type: envelope.error?.type,
                message: envelope.error?.message ?? "anthropic_stream_error"
            )
        default:
            throw AnthropicWireError.invalidEvent
        }
    }
}
