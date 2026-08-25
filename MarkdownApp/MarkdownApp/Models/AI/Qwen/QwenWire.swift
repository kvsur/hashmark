//
//  QwenWire.swift
//  MarkdownApp
//
//  DashScope text-generation / multimodal-generation 专属 wire 类型。
//

import Foundation

nonisolated enum QwenWireError: Error, Equatable {
    case invalidEvent
    case remote(code: String?, message: String)
    case unsupportedInput
    case invalidNativeRoute
}

nonisolated struct QwenUploadedFile: Equatable {
    let id: String
    let name: String
    let mimeType: String
    let purpose: AIFilePurpose
    let extractedText: String?
}

nonisolated struct QwenWireUsage: Decodable, Equatable {
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
    }
}

nonisolated struct QwenWireSearchResult: Decodable, Equatable {
    let siteName: String?
    let index: Int?
    let title: String?
    let url: String?

    enum CodingKeys: String, CodingKey {
        case index, title, url
        case siteName = "site_name"
    }
}

nonisolated struct QwenWireSearchInfo: Decodable, Equatable {
    let searchResults: [QwenWireSearchResult]?

    enum CodingKeys: String, CodingKey {
        case searchResults = "search_results"
    }
}

nonisolated struct QwenWireToolFunction: Decodable, Equatable {
    let name: String?
    let arguments: String?
}

nonisolated struct QwenWireToolCall: Decodable, Equatable {
    let index: Int?
    let id: String?
    let function: QwenWireToolFunction?
}

nonisolated struct QwenWireMessage: Decodable, Equatable {
    let role: String?
    let content: JSONValue?
    let reasoningContent: String?
    let toolCalls: [QwenWireToolCall]?

    enum CodingKeys: String, CodingKey {
        case role, content
        case reasoningContent = "reasoning_content"
        case toolCalls = "tool_calls"
    }
}

nonisolated struct QwenWireChoice: Decodable, Equatable {
    let message: QwenWireMessage?
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }
}

nonisolated struct QwenWireOutput: Decodable, Equatable {
    let choices: [QwenWireChoice]?
    let searchInfo: QwenWireSearchInfo?

    enum CodingKeys: String, CodingKey {
        case choices
        case searchInfo = "search_info"
    }
}

nonisolated struct QwenWireChunk: Decodable, Equatable {
    let output: QwenWireOutput?
    let usage: QwenWireUsage?
    let requestID: String?
    let code: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case output, usage, code, message
        case requestID = "request_id"
    }

    init(data: Data, decoder: JSONDecoder = JSONDecoder()) throws {
        do { self = try decoder.decode(Self.self, from: data) }
        catch { throw QwenWireError.invalidEvent }
        if let message { throw QwenWireError.remote(code: code, message: message) }
    }
}
