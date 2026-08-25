//
//  GLMWebSearchContract.swift
//  MarkdownApp
//
//  GLM 独立 Web Search API 的请求、响应与证据注入契约。
//  Chat Completions 的 tool_choice 不能强制搜索，因此搜索开启时必须先走这里。
//

import Foundation

nonisolated struct GLMStandaloneSearchResult: Codable, Equatable {
    let title: String?
    let content: String?
    let link: String?
    let media: String?
    let icon: String?
    let refer: String?
    let publishDate: String?

    enum CodingKeys: String, CodingKey {
        case title, content, link, media, icon, refer
        case publishDate = "publish_date"
    }
}

nonisolated struct GLMWebSearchEvidence: Equatable {
    let query: String
    let requestID: String
    let results: [GLMStandaloneSearchResult]

    var citations: [AISearchCitation] {
        var seen: Set<String> = []
        return results.compactMap { result in
            guard let rawURL = result.link,
                  let url = AISearchSourceValidator.url(rawURL),
                  seen.insert(url.absoluteString).inserted
            else { return nil }
            return AISearchCitation(
                id: "glm|\(url.absoluteString)",
                title: result.title?.nonEmpty ?? url.host ?? rawURL,
                url: url,
                publisher: result.media?.nonEmpty ?? url.host,
                marker: result.refer,
                provider: .glm,
                query: query,
                sourceIdentity: url.absoluteString
            )
        }
    }
}

nonisolated enum GLMWebSearchContract {
    static let maxQueryCharacters = 70

    static func query(in messages: [AIMessage]) -> String? {
        guard let rawQuery = messages.last(where: { $0.role == .user })?.content else {
            return nil
        }
        let normalized = rawQuery
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(maxQueryCharacters))
    }

    static func makeRequest(
        configuration: ResolvedAIProviderConfiguration,
        query: String,
        requestID: String
    ) throws -> URLRequest {
        guard let url = endpoint(from: configuration.endpointURL) else {
            throw GLMWireError.unsupportedInput
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 120
        request.httpBody = try JSONEncoder().encode(JSONValue.object([
            "search_query": .string(String(query.prefix(maxQueryCharacters))),
            "search_engine": .string("search_pro"),
            "search_intent": .bool(false),
            "count": .number(10),
            "search_recency_filter": .string("noLimit"),
            "content_size": .string("high"),
            "request_id": .string(requestID)
        ]))
        return request
    }

    static func evidence(
        from data: Data,
        query: String,
        fallbackRequestID: String
    ) throws -> GLMWebSearchEvidence {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw GLMWireError.invalidEvent(kind: "data_corrupted", path: "web_search")
        }
        if let error = response.error {
            throw GLMWireError.remote(code: error.code, message: error.message)
        }
        return GLMWebSearchEvidence(
            query: query,
            requestID: response.requestID?.nonEmpty ?? fallbackRequestID,
            results: response.searchResult ?? []
        )
    }

    static func appendingEvidence(
        _ evidence: GLMWebSearchEvidence,
        instruction: String,
        to messages: [AIMessage]
    ) throws -> [AIMessage] {
        let payload = try evidencePayload(evidence)
        let evidenceMessage = AIMessage(
            role: .system,
            content: "\(instruction)\n\n<untrusted_web_search_results>\n\(payload)\n</untrusted_web_search_results>"
        )
        var result = messages
        let index = result.firstIndex(where: { $0.role != .system }) ?? result.endIndex
        result.insert(evidenceMessage, at: index)
        return result
    }

    private static func endpoint(from chatEndpoint: URL) -> URL? {
        let chatSuffix = "/api/paas/v4/chat/completions"
        let searchSuffix = "/api/paas/v4/web_search"
        guard var components = URLComponents(
            url: chatEndpoint,
            resolvingAgainstBaseURL: false
        ), components.path.hasSuffix(chatSuffix) else { return nil }
        components.path = String(components.path.dropLast(chatSuffix.count)) + searchSuffix
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func evidencePayload(_ evidence: GLMWebSearchEvidence) throws -> String {
        let items = evidence.results.prefix(10).enumerated().map { index, result in
            JSONValue.object([
                "index": .number(Double(index + 1)),
                "title": .string(result.title ?? ""),
                "url": .string(result.link ?? ""),
                "publisher": .string(result.media ?? ""),
                "published_at": .string(result.publishDate ?? ""),
                "content": .string(String((result.content ?? "").prefix(4_000)))
            ])
        }
        let data = try JSONEncoder().encode(JSONValue.object([
            "query": .string(evidence.query),
            "request_id": .string(evidence.requestID),
            "results": .array(items)
        ]))
        guard let value = String(data: data, encoding: .utf8) else {
            throw GLMWireError.invalidEvent(kind: "encoding", path: "web_search_evidence")
        }
        return value
    }

    private struct Response: Decodable {
        let requestID: String?
        let searchResult: [GLMStandaloneSearchResult]?
        let error: GLMWireErrorPayload?

        enum CodingKeys: String, CodingKey {
            case error
            case requestID = "request_id"
            case searchResult = "search_result"
        }
    }
}

private extension String {
    nonisolated var nonEmpty: String? { isEmpty ? nil : self }
}
