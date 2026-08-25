//
//  AIDomain.swift
//  MarkdownApp
//
//  Provider Adapter 与会话/UI 之间的中立 AIGC 状态。Wire payload 不进入这些类型。
//

import Foundation

nonisolated enum AIGenerationPhase: Equatable {
    case preparingAttachments
    case uploading
    case connecting
    case thinking
    case searching
    case usingTool
    case generating
    case finalizing
}

nonisolated struct AISearchCitation: Equatable, Identifiable {
    let id: String
    let title: String
    let url: URL
    let publisher: String?
    let marker: String?
    let provider: AIProvider
    let query: String?
    let sourceIdentity: String?
    let startIndex: Int?
    let endIndex: Int?

    init(
        id: String,
        title: String,
        url: URL,
        publisher: String?,
        marker: String?,
        provider: AIProvider,
        query: String? = nil,
        sourceIdentity: String? = nil,
        startIndex: Int? = nil,
        endIndex: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.publisher = publisher
        self.marker = marker
        self.provider = provider
        self.query = query
        self.sourceIdentity = sourceIdentity
        self.startIndex = startIndex
        self.endIndex = endIndex
    }
}

nonisolated enum AISearchSourceValidator {
    static func url(_ rawValue: String) -> URL? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host != nil
        else { return nil }
        return url
    }
}

nonisolated struct AISearchActivity: Equatable {
    let provider: AIProvider
    let query: String?
    let requestID: String?
}

nonisolated struct AISearchContinuation: Equatable {
    let provider: AIProvider
    let callID: String
    let toolName: String
    let arguments: String
}

nonisolated enum AISearchEvent: Equatable {
    case started(AISearchActivity)
    case citation(AISearchCitation)
    case continuationRequired(AISearchContinuation)
    case completed(AIProvider)
}

nonisolated enum AISearchState: Equatable {
    case idle
    case searching(provider: AIProvider, query: String?)
    case awaitingContinuation(provider: AIProvider)
    case completed(provider: AIProvider)
}

/// 搜索旁路状态的纯 reducer：正文不接触 source，重复来源也只展示一次。
nonisolated struct AISearchTimeline: Equatable {
    private(set) var state: AISearchState = .idle
    private(set) var citations: [AISearchCitation] = []
    private(set) var continuation: AISearchContinuation?

    mutating func reset() {
        state = .idle
        citations = []
        continuation = nil
    }

    mutating func apply(_ event: AISearchEvent) {
        switch event {
        case .started(let activity):
            state = .searching(provider: activity.provider, query: activity.query)
        case .citation(let citation):
            if !citations.contains(where: { identity($0) == identity(citation) }) {
                citations.append(citation)
            }
            state = .searching(provider: citation.provider, query: citation.query)
        case .continuationRequired(let value):
            continuation = value
            state = .awaitingContinuation(provider: value.provider)
        case .completed(let provider):
            continuation = nil
            state = .completed(provider: provider)
        }
    }

    private func identity(_ citation: AISearchCitation) -> String {
        citation.sourceIdentity ?? citation.url.absoluteString
    }
}

nonisolated struct AIUsage: Equatable {
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?
}

nonisolated enum AIFilePurpose: Equatable {
    case directInput
    case extraction
    case retrieval
}

nonisolated struct AIProviderFileReference: Equatable {
    let provider: AIProvider
    let id: String
    let purpose: AIFilePurpose
    let expiresAt: Date?
    /// 仅供同一家 Adapter 恢复其原生 URI、提取文本或 store identity。
    /// UI 与其他 Provider 不得解释此 payload。
    let transportPayload: JSONValue?

    init(
        provider: AIProvider,
        id: String,
        purpose: AIFilePurpose,
        expiresAt: Date?,
        transportPayload: JSONValue? = nil
    ) {
        self.provider = provider
        self.id = id
        self.purpose = purpose
        self.expiresAt = expiresAt
        self.transportPayload = transportPayload
    }

    func validated(for expectedProvider: AIProvider, now: Date = .now) throws
        -> AIProviderFileReference
    {
        guard provider == expectedProvider else { throw AIProviderFileValidationError.providerMismatch }
        if let expiresAt, expiresAt <= now { throw AIProviderFileValidationError.expiredReference }
        return self
    }
}

nonisolated enum AIProviderFileValidationError: Error, Equatable {
    case providerMismatch
    case expiredReference
}

nonisolated enum AIFileState: Equatable {
    case validating
    case uploading(progress: Double?)
    case extracting
    case ready(AIProviderFileReference)
    case failed(String)
    case expired
}

nonisolated struct AIFileUploadRequest: Equatable {
    let name: String
    let mimeType: String
    let data: Data
    let purpose: AIFilePurpose
}

nonisolated struct AIProviderContinuation: Equatable {
    let provider: AIProvider
    let kind: String
    let payload: JSONValue
}
