//
//  OpenAIResponsesWire.swift
//  MarkdownApp
//
//  OpenAI Responses 第一方 wire 类型。它们只在 OpenAI Adapter 内存在，不能进入
//  Provider-neutral 会话或被其他 Provider 复用。
//

import Foundation

nonisolated enum OpenAIResponsesWireError: Error, Equatable {
    case invalidEvent
    case remote(String)
    case unsupportedInput
    case emptyContinuation
}

nonisolated struct OpenAIResponsesWireUsage: Decodable, Equatable {
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
    }
}

nonisolated struct OpenAIResponsesWireErrorPayload: Decodable, Equatable {
    let code: String?
    let message: String?
}

nonisolated struct OpenAIResponsesWireIncompleteDetails: Decodable, Equatable {
    let reason: String?
}

nonisolated struct OpenAIResponsesWireSource: Decodable, Equatable {
    let title: String?
    let url: String?
    let publisher: String?
}

nonisolated struct OpenAIResponsesWireAction: Decodable, Equatable {
    let type: String?
    let sources: [OpenAIResponsesWireSource]?
}

nonisolated struct OpenAIResponsesWireAnnotation: Decodable, Equatable {
    let type: String?
    let title: String?
    let url: String?
    let startIndex: Int?
    let endIndex: Int?

    enum CodingKeys: String, CodingKey {
        case type, title, url
        case startIndex = "start_index"
        case endIndex = "end_index"
    }
}

nonisolated struct OpenAIResponsesWireContent: Decodable, Equatable {
    let type: String?
    let text: String?
    let annotations: [OpenAIResponsesWireAnnotation]?
}

nonisolated struct OpenAIResponsesWireFileSearchResult: Decodable, Equatable {
    let fileID: String?
    let filename: String?

    enum CodingKeys: String, CodingKey {
        case fileID = "file_id"
        case filename
    }
}

nonisolated struct OpenAIResponsesWireOutputItem: Decodable, Equatable {
    let id: String?
    let type: String
    let status: String?
    let callID: String?
    let name: String?
    let arguments: String?
    let action: OpenAIResponsesWireAction?
    let content: [OpenAIResponsesWireContent]?
    let results: [OpenAIResponsesWireFileSearchResult]?

    enum CodingKeys: String, CodingKey {
        case id, type, status, name, arguments, action, content, results
        case callID = "call_id"
    }
}

nonisolated struct OpenAIResponsesWireResponse: Decodable, Equatable {
    let id: String
    let status: String?
    let output: [OpenAIResponsesWireOutputItem]?
    let usage: OpenAIResponsesWireUsage?
    let error: OpenAIResponsesWireErrorPayload?
    let incompleteDetails: OpenAIResponsesWireIncompleteDetails?

    enum CodingKeys: String, CodingKey {
        case id, status, output, usage, error
        case incompleteDetails = "incomplete_details"
    }
}

private nonisolated struct OpenAIResponsesWireEnvelope: Decodable {
    let type: String
    let delta: String?
    let text: String?
    let arguments: String?
    let name: String?
    let callID: String?
    let itemID: String?
    let item: OpenAIResponsesWireOutputItem?
    let response: OpenAIResponsesWireResponse?
    let error: OpenAIResponsesWireErrorPayload?

    enum CodingKeys: String, CodingKey {
        case type, delta, text, arguments, name, item, response, error
        case callID = "call_id"
        case itemID = "item_id"
    }
}

nonisolated enum OpenAIResponsesWireEvent: Equatable {
    case created(OpenAIResponsesWireResponse)
    case inProgress(OpenAIResponsesWireResponse)
    case outputTextDelta(String)
    case reasoningSummaryDelta(itemID: String, delta: String)
    case reasoningSummaryDone(itemID: String, text: String?)
    case functionArgumentsDone(itemID: String, callID: String?, name: String, arguments: String)
    case outputItemAdded(OpenAIResponsesWireOutputItem)
    case outputItemDone(OpenAIResponsesWireOutputItem)
    case webSearchActivity
    case fileSearchActivity
    case refusalDelta(String)
    case completed(OpenAIResponsesWireResponse)
    case incomplete(OpenAIResponsesWireResponse)
    case failed(String)
    case unknown(String)

    init(data: Data, decoder: JSONDecoder = JSONDecoder()) throws {
        let envelope: OpenAIResponsesWireEnvelope
        do {
            envelope = try decoder.decode(OpenAIResponsesWireEnvelope.self, from: data)
        } catch {
            throw OpenAIResponsesWireError.invalidEvent
        }

        switch envelope.type {
        case "response.created":
            guard let response = envelope.response else { throw OpenAIResponsesWireError.invalidEvent }
            self = .created(response)
        case "response.in_progress", "response.queued":
            guard let response = envelope.response else { throw OpenAIResponsesWireError.invalidEvent }
            self = .inProgress(response)
        case "response.output_text.delta":
            guard let delta = envelope.delta else { throw OpenAIResponsesWireError.invalidEvent }
            self = .outputTextDelta(delta)
        case "response.reasoning_summary_text.delta":
            guard let delta = envelope.delta else { throw OpenAIResponsesWireError.invalidEvent }
            self = .reasoningSummaryDelta(itemID: envelope.itemID ?? "reasoning", delta: delta)
        case "response.reasoning_summary_text.done":
            self = .reasoningSummaryDone(itemID: envelope.itemID ?? "reasoning", text: envelope.text)
        case "response.function_call_arguments.done":
            guard let name = envelope.name, let arguments = envelope.arguments else {
                throw OpenAIResponsesWireError.invalidEvent
            }
            self = .functionArgumentsDone(
                itemID: envelope.itemID ?? envelope.callID ?? name,
                callID: envelope.callID,
                name: name,
                arguments: arguments
            )
        case "response.output_item.added":
            guard let item = envelope.item else { throw OpenAIResponsesWireError.invalidEvent }
            self = .outputItemAdded(item)
        case "response.output_item.done":
            guard let item = envelope.item else { throw OpenAIResponsesWireError.invalidEvent }
            self = .outputItemDone(item)
        case "response.web_search_call.in_progress",
             "response.web_search_call.searching",
             "response.web_search_call.completed":
            self = .webSearchActivity
        case "response.file_search_call.in_progress",
             "response.file_search_call.searching",
             "response.file_search_call.completed":
            self = .fileSearchActivity
        case "response.refusal.delta":
            guard let delta = envelope.delta else { throw OpenAIResponsesWireError.invalidEvent }
            self = .refusalDelta(delta)
        case "response.completed":
            guard let response = envelope.response else { throw OpenAIResponsesWireError.invalidEvent }
            self = .completed(response)
        case "response.incomplete":
            guard let response = envelope.response else { throw OpenAIResponsesWireError.invalidEvent }
            self = .incomplete(response)
        case "response.failed":
            let payload = envelope.response?.error ?? envelope.error
            self = .failed(payload?.message ?? payload?.code ?? "response_failed")
        case "error":
            self = .failed(envelope.error?.message ?? envelope.error?.code ?? "stream_error")
        default:
            self = .unknown(envelope.type)
        }
    }
}
