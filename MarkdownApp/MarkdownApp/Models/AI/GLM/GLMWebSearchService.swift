//
//  GLMWebSearchService.swift
//  MarkdownApp
//
//  GLM 独立 Web Search API 的传输层；只记录请求阶段与状态，不记录查询或结果正文。
//

import Foundation

actor GLMWebSearchService {
    private let configuration: ResolvedAIProviderConfiguration
    private let session: URLSession

    init(configuration: ResolvedAIProviderConfiguration, session: URLSession) {
        self.configuration = configuration
        self.session = session
    }

    func search(query: String) async throws -> GLMWebSearchEvidence {
        let requestID = UUID().uuidString
        let request = try GLMWebSearchContract.makeRequest(
            configuration: configuration,
            query: query,
            requestID: requestID
        )
        AIDiagnostics.requestStarted(
            provider: .glm,
            request: request,
            model: configuration.model,
            messageCount: 1,
            appToolCount: 0,
            webSearchEnabled: true
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIError.stream("invalid_http_response")
        }
        AIDiagnostics.response(http, request: request)
        guard (200..<300).contains(http.statusCode) else {
            throw AIError.http(
                status: http.statusCode,
                body: String(data: data.prefix(32_768), encoding: .utf8)
            )
        }
        return try GLMWebSearchContract.evidence(
            from: data,
            query: query,
            fallbackRequestID: requestID
        )
    }
}
