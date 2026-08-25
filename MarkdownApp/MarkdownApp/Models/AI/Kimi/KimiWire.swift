//
//  KimiWire.swift
//  MarkdownApp
//
//  Moonshot chat/files 第一方 wire 类型。即使字段相似，也不复用 OpenAI 类型。
//

import Foundation

nonisolated enum KimiWireError: Error, Equatable {
    case invalidEvent
    case remote(type: String?, message: String)
    case unsupportedInput
    case missingFormulaTool
    case invalidFormulaResult
    case unexpectedFormulaToolCall
    case missingWebSearchPolicy
}

nonisolated struct KimiUploadedFile: Equatable {
    let id: String
    let name: String
    let mimeType: String
    let purpose: AIFilePurpose
    let extractedText: String?
}

nonisolated enum KimiNativeEndpoints {
    static func files(from chatCompletions: URL) -> URL {
        chatCompletions
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("files")
    }

    static func formulaTools(from chatCompletions: URL) -> URL {
        formulaRoot(from: chatCompletions).appendingPathComponent("tools")
    }

    static func formulaFibers(from chatCompletions: URL) -> URL {
        formulaRoot(from: chatCompletions).appendingPathComponent("fibers")
    }

    private static func formulaRoot(from chatCompletions: URL) -> URL {
        chatCompletions
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("formulas")
            .appendingPathComponent("moonshot")
            .appendingPathComponent("web-search:latest")
    }
}

nonisolated struct KimiWireErrorPayload: Decodable, Equatable {
    let type: String?
    let message: String
}

nonisolated struct KimiWireUsage: Decodable, Equatable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

nonisolated struct KimiWireToolFunction: Decodable, Equatable {
    let name: String?
    let arguments: String?
}

nonisolated struct KimiWireToolCall: Decodable, Equatable {
    let index: Int?
    let id: String?
    let function: KimiWireToolFunction?
}

nonisolated struct KimiWireDelta: Decodable, Equatable {
    let content: String?
    let reasoningContent: String?
    let toolCalls: [KimiWireToolCall]?

    enum CodingKeys: String, CodingKey {
        case content
        case reasoningContent = "reasoning_content"
        case toolCalls = "tool_calls"
    }
}

nonisolated struct KimiWireChoice: Decodable, Equatable {
    let delta: KimiWireDelta?
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case delta
        case finishReason = "finish_reason"
    }
}

nonisolated struct KimiWireChunk: Decodable, Equatable {
    let id: String?
    let choices: [KimiWireChoice]?
    let usage: KimiWireUsage?
    let error: KimiWireErrorPayload?

    init(data: Data, decoder: JSONDecoder = JSONDecoder()) throws {
        do { self = try decoder.decode(Self.self, from: data) }
        catch { throw KimiWireError.invalidEvent }
        if let error { throw KimiWireError.remote(type: error.type, message: error.message) }
    }
}
