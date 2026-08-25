//
//  GLMWire.swift
//  MarkdownApp
//
//  BigModel chat/files 第一方 wire 类型。
//

import Foundation

nonisolated enum GLMWireError: Error, Equatable {
    case invalidEvent(kind: String, path: String)
    case remote(code: String?, message: String)
    case unsupportedInput
    case missingWebSearchEvidence
}

nonisolated struct GLMUploadedFile: Equatable {
    let id: String
    let url: String
    let name: String
    let mimeType: String
    let purpose: AIFilePurpose
}

nonisolated struct GLMWireErrorPayload: Decodable, Equatable {
    let code: String?
    let message: String

    private enum CodingKeys: String, CodingKey {
        case code, message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? container.decode(String.self, forKey: .code) {
            code = value
        } else if let value = try? container.decode(Int.self, forKey: .code) {
            // 线上错误帧存在数字错误码；规范化后保留 typed error，不让它退化成 invalidEvent。
            code = String(value)
        } else {
            code = nil
        }
        message = (try? container.decode(String.self, forKey: .message)) ?? "remote_error"
    }
}

nonisolated struct GLMWireUsage: Decodable, Equatable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

nonisolated struct GLMWireSearchResult: Decodable, Equatable {
    let title: String?
    let link: String?
    let content: String?
    let media: String?
    let refer: String?
}

nonisolated struct GLMWireToolFunction: Decodable, Equatable {
    let name: String?
    let arguments: String?
}

nonisolated struct GLMWireToolCall: Decodable, Equatable {
    let index: Int?
    let id: String?
    let type: String?
    let function: GLMWireToolFunction?
}

nonisolated struct GLMWireDelta: Decodable, Equatable {
    let content: String?
    let reasoningContent: String?
    let toolCalls: [GLMWireToolCall]?

    enum CodingKeys: String, CodingKey {
        case content
        case reasoningContent = "reasoning_content"
        case toolCalls = "tool_calls"
    }
}

nonisolated struct GLMWireChoice: Decodable, Equatable {
    let delta: GLMWireDelta?
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case delta
        case finishReason = "finish_reason"
    }
}

nonisolated struct GLMWireChunk: Decodable, Equatable {
    let id: String?
    let requestID: String?
    let choices: [GLMWireChoice]?
    let usage: GLMWireUsage?
    let webSearch: [GLMWireSearchResult]?
    let error: GLMWireErrorPayload?

    enum CodingKeys: String, CodingKey {
        case id, choices, usage, error
        case requestID = "request_id"
        case webSearch = "web_search"
    }

    init(data: Data, decoder: JSONDecoder = JSONDecoder()) throws {
        do {
            self = try decoder.decode(Self.self, from: data)
        } catch {
            let details = decodingFailureDetails(error)
            throw GLMWireError.invalidEvent(kind: details.kind, path: details.path)
        }
        if let error { throw GLMWireError.remote(code: error.code, message: error.message) }
    }
}

private nonisolated func decodingFailureDetails(_ error: Error) -> (kind: String, path: String) {
    let result: (String, [any CodingKey])
    switch error {
    case .typeMismatch(_, let context) as DecodingError:
        result = ("type_mismatch", context.codingPath)
    case .valueNotFound(_, let context) as DecodingError:
        result = ("value_not_found", context.codingPath)
    case .keyNotFound(let key, let context) as DecodingError:
        result = ("key_not_found", context.codingPath + [key])
    case .dataCorrupted(let context) as DecodingError:
        result = ("data_corrupted", context.codingPath)
    default:
        result = ("unknown", [])
    }
    let path = result.1.map(\.stringValue).joined(separator: ".")
    return (result.0, path.isEmpty ? "root" : path)
}
