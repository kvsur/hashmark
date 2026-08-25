//
//  AIAttachmentLifecycle.swift
//  MarkdownApp
//
//  UI 与五家 Adapter 之间的 typed attachment intent/state。原生 file payload 仍由 Provider 所有。
//

import Foundation

nonisolated enum AIAttachmentIntent: Equatable {
    case textContext
    case directInput
    case uploadReference
    case extraction
    case retrieval

    var filePurpose: AIFilePurpose? {
        switch self {
        case .textContext: nil
        case .directInput, .uploadReference: .directInput
        case .extraction: .extraction
        case .retrieval: .retrieval
        }
    }

    var diagnosticName: String {
        switch self {
        case .textContext: "text-context"
        case .directInput: "direct-input"
        case .uploadReference: "upload-reference"
        case .extraction: "extraction"
        case .retrieval: "retrieval"
        }
    }
}

nonisolated enum AIAttachmentLifecycleState: Equatable {
    case local
    case validating
    case uploading(progress: Double?)
    case uploaded(AIProviderFileReference)
    case extracting
    case ready(AIProviderFileReference?)
    case failed(AIAttachmentIssue)
    case expired
}

nonisolated enum AIAttachmentIssue: Error, Equatable {
    case unsupportedByModel
    case unsupportedMIME(String)
    case itemTooLarge(maxBytes: Int)
    case tooMany(maxCount: Int)
    case totalTooLarge(maxBytes: Int)
    case mixedMediaUnsupported
    case providerMismatch
    case expiredReference
    case uploadUnavailable
    case explicitTextFallbackRequired

    @MainActor var userMessage: String {
        switch self {
        case .unsupportedByModel, .unsupportedMIME, .mixedMediaUnsupported:
            LocalizationController.string("Not available for this provider")
        case .itemTooLarge, .totalTooLarge:
            LocalizationController.string("Some files are too large to attach.")
        case .tooMany:
            LocalizationController.string("Attachment limit reached.")
        case .providerMismatch, .expiredReference, .uploadUnavailable,
             .explicitTextFallbackRequired:
            LocalizationController.string("Some files couldn't be added.")
        }
    }
}

nonisolated struct AIAttachmentPreparation: Equatable, Identifiable {
    let id: UUID
    let name: String
    let mimeType: String
    let byteCount: Int
    let intent: AIAttachmentIntent
    var state: AIAttachmentLifecycleState
}

nonisolated struct AIPreparedAttachmentTurn: Equatable {
    let messages: [AIMessage]
    let preparations: [AIAttachmentPreparation]
    let references: [AIProviderFileReference]
}
