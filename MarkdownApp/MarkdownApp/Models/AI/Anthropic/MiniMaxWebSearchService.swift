//
//  MiniMaxWebSearchService.swift
//  MarkdownApp
//
//  MiniMax 的 Anthropic-compatible Messages 接口不代执行 Anthropic server tools。
//  Coding Plan Web Search 必须由客户端单独调用，再以标准 tool_result 交回模型。
//

import Foundation
#if DEBUG
import OSLog
#endif

nonisolated struct MiniMaxWebSearchResult: Equatable {
    let toolResult: String
    let citations: [AISearchCitation]
}

nonisolated enum MiniMaxWebSearchContract {
    static let toolName = "web_search"

    static func matches(_ configuration: ResolvedAIProviderConfiguration) -> Bool {
        guard configuration.provider == .anthropic,
              let host = configuration.endpointURL.host?.lowercased()
        else { return false }
        return host == "api.minimaxi.com" || host == "api.minimax.io"
    }

    static func makeRequest(
        configuration: ResolvedAIProviderConfiguration,
        query: String
    ) throws -> URLRequest {
        guard var components = URLComponents(url: configuration.endpointURL, resolvingAgainstBaseURL: false),
              components.scheme != nil,
              components.host != nil
        else { throw AnthropicWireError.invalidEvent }
        components.path = "/v1/coding_plan/search"
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { throw AnthropicWireError.invalidEvent }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("Minimax-MCP", forHTTPHeaderField: "MM-API-Source")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 120
        request.httpBody = try JSONEncoder().encode(["q": query])
        return request
    }

    static func decode(_ data: Data) throws -> MiniMaxWebSearchResult {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw AnthropicWireError.invalidEvent
        }
        if let status = response.baseResp?.statusCode, status != 0 {
            throw AnthropicWireError.remote(
                type: "minimax_search_\(status)",
                message: response.baseResp?.statusMessage ?? "minimax_search_failed"
            )
        }
        let payload = ToolPayload(
            organic: response.organic ?? [],
            relatedSearches: response.relatedSearches ?? []
        )
        let encoded = try JSONEncoder().encode(payload)
        guard let toolResult = String(data: encoded, encoding: .utf8) else {
            throw AnthropicWireError.invalidEvent
        }
        let citations = payload.organic.compactMap { item -> AISearchCitation? in
            guard let url = AISearchSourceValidator.url(item.link) else { return nil }
            return AISearchCitation(
                id: "anthropic|minimax|\(url.absoluteString)",
                title: item.title.isEmpty ? (url.host ?? item.link) : item.title,
                url: url,
                publisher: url.host,
                marker: nil,
                provider: .anthropic,
                sourceIdentity: url.absoluteString
            )
        }
        return MiniMaxWebSearchResult(toolResult: toolResult, citations: citations)
    }

    static func appendingResult(
        _ result: MiniMaxWebSearchResult,
        query: String,
        to messages: [AIMessage]
    ) throws -> [AIMessage] {
        let argumentsData = try JSONEncoder().encode(["query": query])
        guard let arguments = String(data: argumentsData, encoding: .utf8) else {
            throw AnthropicWireError.invalidEvent
        }
        let callID = "minimax_web_search_\(UUID().uuidString)"
        return messages + [
            .assistant(
                text: "",
                toolCalls: [AIToolCall(
                    id: callID,
                    name: toolName,
                    arguments: arguments
                )]
            ),
            .toolResult(callId: callID, name: toolName, content: result.toolResult)
        ]
    }

    private struct Response: Decodable {
        let organic: [SearchItem]?
        let relatedSearches: [RelatedSearch]?
        let baseResp: BaseResponse?

        enum CodingKeys: String, CodingKey {
            case organic
            case relatedSearches = "related_searches"
            case baseResp = "base_resp"
        }
    }

    private struct BaseResponse: Decodable {
        let statusCode: Int?
        let statusMessage: String?

        enum CodingKeys: String, CodingKey {
            case statusCode = "status_code"
            case statusMessage = "status_msg"
        }
    }

    private struct ToolPayload: Encodable {
        let organic: [SearchItem]
        let relatedSearches: [RelatedSearch]

        enum CodingKeys: String, CodingKey {
            case organic
            case relatedSearches = "related_searches"
        }
    }

    private struct SearchItem: Codable {
        let title: String
        let link: String
        let snippet: String?
        let date: String?
    }

    private struct RelatedSearch: Codable {
        let query: String
    }
}

actor MiniMaxWebSearchService {
#if DEBUG
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "MarkdownApp",
        category: "AI.API"
    )
#endif

    private let configuration: ResolvedAIProviderConfiguration
    private let session: URLSession

    init(configuration: ResolvedAIProviderConfiguration, session: URLSession) {
        self.configuration = configuration
        self.session = session
    }

    func search(query: String) async throws -> MiniMaxWebSearchResult {
        let request = try MiniMaxWebSearchContract.makeRequest(
            configuration: configuration,
            query: query
        )
#if DEBUG
        Self.logger.notice(
            "[AI-Debug] minimax-search request-start host=\(request.url?.host ?? "unknown", privacy: .public) path=\(request.url?.path ?? "unknown", privacy: .public)"
        )
#endif
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AnthropicWireError.invalidEvent
        }
#if DEBUG
        Self.logger.notice(
            "[AI-Debug] minimax-search response status=\(http.statusCode)"
        )
#endif
        guard (200..<300).contains(http.statusCode) else {
            throw AnthropicWireError.remote(
                type: "http_status_\(http.statusCode)",
                message: String(data: data.prefix(32_768), encoding: .utf8)
                    ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            )
        }
        return try MiniMaxWebSearchContract.decode(data)
    }
}
