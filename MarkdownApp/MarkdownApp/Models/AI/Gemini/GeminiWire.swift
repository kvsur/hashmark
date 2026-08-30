//
//  GeminiWire.swift
//  MarkdownApp
//
//  Gemini Interactions wire types。generateContent 与 OpenAI-compatible 类型不得进入此模块。
//

import Foundation

nonisolated enum GeminiWireError: Error, Equatable {
    case invalidEvent
    case remote(code: String?, message: String)
    case unsupportedInput
    case missingUploadURL
    case missingTerminalInteraction
}

nonisolated struct GeminiUploadedFile: Equatable {
    let name: String
    let uri: String
    let mimeType: String
    let purpose: AIFilePurpose
}

nonisolated struct GeminiWireUsage: Decodable, Equatable {
    let totalTokens: Int?
    let inputTokens: Int?
    let outputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case totalTokens = "total_tokens"
        case inputTokens = "total_input_tokens"
        case outputTokens = "total_output_tokens"
    }
}

nonisolated struct GeminiWireErrorPayload: Decodable, Equatable {
    let code: String?
    let message: String?
    let status: String?

    static func decodeResponse(from data: Data) -> Self? {
        if let envelope = try? JSONDecoder().decode(GeminiWireErrorEnvelope.self, from: data) {
            return envelope.error
        }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

private nonisolated struct GeminiWireErrorEnvelope: Decodable {
    let error: GeminiWireErrorPayload
}

nonisolated struct GeminiWireAnnotation: Decodable, Equatable {
    let type: String?
    let url: String?
    let title: String?
    let startIndex: Int?
    let endIndex: Int?
    let fileName: String?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case type, url, title, source
        case startIndex = "start_index"
        case endIndex = "end_index"
        case fileName = "file_name"
    }
}

nonisolated struct GeminiWireContent: Decodable, Equatable {
    let type: String
    let text: String?
    let annotations: [GeminiWireAnnotation]?
}

nonisolated struct GeminiWireStep: Decodable, Equatable {
    let id: String?
    let type: String
    let name: String?
    let callID: String?
    let arguments: JSONValue?
    let signature: String?
    let summary: [GeminiWireContent]?
    let content: [GeminiWireContent]?
    let result: JSONValue?

    enum CodingKeys: String, CodingKey {
        case id, type, name, arguments, signature, summary, content, result
        case callID = "call_id"
    }
}

nonisolated struct GeminiWireInteraction: Decodable, Equatable {
    let id: String
    let status: String?
    let usage: GeminiWireUsage?
    let steps: [GeminiWireStep]?
    let error: GeminiWireErrorPayload?
}

private nonisolated struct GeminiWireDelta: Decodable {
    let type: String?
    let text: String?
    let signature: String?
    let name: String?
    let callID: String?
    let arguments: JSONValue?
    let partialArguments: String?
    let annotations: [GeminiWireAnnotation]?

    enum CodingKeys: String, CodingKey {
        case type, text, signature, name, arguments, annotations
        case callID = "call_id"
        case partialArguments = "partial_arguments"
    }
}

private nonisolated struct GeminiWireEnvelope: Decodable {
    let eventType: String
    let index: Int?
    let interaction: GeminiWireInteraction?
    let step: GeminiWireStep?
    let delta: GeminiWireDelta?
    let error: GeminiWireErrorPayload?

    enum CodingKeys: String, CodingKey {
        case index, interaction, step, delta, error
        case eventType = "event_type"
    }
}

nonisolated enum GeminiWireEvent: Equatable {
    case interactionCreated(GeminiWireInteraction)
    case stepStart(index: Int, step: GeminiWireStep)
    case stepDelta(
        index: Int,
        type: String?,
        text: String?,
        signature: String?,
        name: String?,
        callID: String?,
        arguments: JSONValue?,
        annotations: [GeminiWireAnnotation]
    )
    case stepStop(index: Int, step: GeminiWireStep?)
    case interactionCompleted(GeminiWireInteraction)
    case interactionFailed(code: String?, message: String)
    case unknown(String)

    init(data: Data, decoder: JSONDecoder = JSONDecoder()) throws {
        let envelope: GeminiWireEnvelope
        do { envelope = try decoder.decode(GeminiWireEnvelope.self, from: data) }
        catch { throw GeminiWireError.invalidEvent }

        switch envelope.eventType {
        case "interaction.created", "interaction.in_progress":
            guard let interaction = envelope.interaction else { throw GeminiWireError.invalidEvent }
            self = .interactionCreated(interaction)
        case "step.start":
            guard let index = envelope.index, let step = envelope.step else {
                throw GeminiWireError.invalidEvent
            }
            self = .stepStart(index: index, step: step)
        case "step.delta":
            guard let index = envelope.index, let delta = envelope.delta else {
                throw GeminiWireError.invalidEvent
            }
            self = .stepDelta(
                index: index,
                type: delta.type,
                text: delta.text,
                signature: delta.signature,
                name: delta.name,
                callID: delta.callID,
                arguments: delta.arguments ?? delta.partialArguments.map(JSONValue.string),
                annotations: delta.annotations ?? []
            )
        case "step.stop":
            guard let index = envelope.index else { throw GeminiWireError.invalidEvent }
            self = .stepStop(index: index, step: envelope.step)
        case "interaction.completed":
            guard let interaction = envelope.interaction else { throw GeminiWireError.invalidEvent }
            self = .interactionCompleted(interaction)
        case "interaction.failed", "interaction.cancelled", "error":
            let payload = envelope.interaction?.error ?? envelope.error
            self = .interactionFailed(
                code: payload?.code,
                message: payload?.message ?? payload?.status ?? "gemini_interaction_failed"
            )
        default:
            self = .unknown(envelope.eventType)
        }
    }
}
