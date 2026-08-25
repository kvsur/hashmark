//
//  AIModelCatalogService.swift
//  MarkdownApp
//
//  五家第一方目录 orchestration：Provider wire 解析由独立 discovery strategy 所有。
//

import Foundation

nonisolated struct AIModelCatalogSnapshot: Codable, Equatable, Sendable {
    static let schemaVersion = 2
    static let cacheTTL: TimeInterval = 24 * 60 * 60
    static let lastGoodRetention: TimeInterval = 30 * 24 * 60 * 60

    let version: Int
    let profileID: UUID
    let provider: AIProvider
    let normalizedEndpoint: String
    let models: [AIModelDescriptor]
    let fetchedAt: Date
    let manifestVersion: String
    let protocolVersion: String

    var modelIDs: [String] {
        models.filter(\.isWritingCandidate).map(\.id).sorted()
    }

    var scopeKey: String {
        "\(profileID.uuidString.lowercased())|\(provider.rawValue)|\(normalizedEndpoint)"
    }

    func isStale(at date: Date = .now) -> Bool {
        date.timeIntervalSince(fetchedAt) > Self.cacheTTL
    }

    func isOutsideLastGoodRetention(at date: Date = .now) -> Bool {
        date.timeIntervalSince(fetchedAt) > Self.lastGoodRetention
    }

    init(
        profileID: UUID,
        provider: AIProvider,
        normalizedEndpoint: String,
        models: [AIModelDescriptor],
        fetchedAt: Date,
        manifestVersion: String = AIProviderRegistry.manifestContentVersion,
        protocolVersion: String = AIProviderRegistry.protocolEvidenceVersion
    ) {
        self.version = Self.schemaVersion
        self.profileID = profileID
        self.provider = provider
        self.normalizedEndpoint = normalizedEndpoint
        self.models = models
        self.fetchedAt = fetchedAt
        self.manifestVersion = manifestVersion
        self.protocolVersion = protocolVersion
    }

    // v1 调用点兼容；真实 profile 在 versioned settings 迁移后提供。
    init(provider: AIProvider, modelIDs: [String], fetchedAt: Date) {
        self.init(
            profileID: AIModelCatalogScope.legacyProfileID,
            provider: provider,
            normalizedEndpoint: "legacy",
            models: Array(Set(modelIDs.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty })).sorted().map {
                AIModelDiscoveryParsing.descriptor(id: $0, observedAt: fetchedAt)
            },
            fetchedAt: fetchedAt
        )
    }

    func replacing(models: [AIModelDescriptor]) -> AIModelCatalogSnapshot {
        AIModelCatalogSnapshot(
            profileID: profileID,
            provider: provider,
            normalizedEndpoint: normalizedEndpoint,
            models: models,
            fetchedAt: fetchedAt,
            manifestVersion: manifestVersion,
            protocolVersion: protocolVersion
        )
    }
}

nonisolated enum AIModelCatalogError: Error, Equatable {
    case unavailable
    case invalidEndpoint
    case invalidResponse
    case emptyResponse
    case paginationLimit
    case http(Int)
}

final class AIModelCatalogService {
    private static let maximumCatalogPages = 20
    private let session: URLSession
    private let now: @Sendable () -> Date

    init(
        session: URLSession = .shared,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.session = session
        self.now = now
    }

    func fetch(
        for config: AIConfig,
        profileID: UUID = AIModelCatalogScope.legacyProfileID
    ) async throws -> AIModelCatalogSnapshot {
        let strategy = AIModelDiscoveryStrategyFactory.make(for: config.provider)
        guard strategy.isAvailable else { throw AIModelCatalogError.unavailable }
        let resolved = try AIProviderRegistry.resolve(config)
        var cursor: AIModelDiscoveryCursor?
        var descriptors: [String: AIModelDescriptor] = [:]
        let observedAt = now()

        for pageNumber in 0..<Self.maximumCatalogPages {
            let request = try Self.makeRequest(
                resolved: resolved,
                strategy: strategy,
                cursor: cursor
            )
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AIModelCatalogError.invalidResponse
            }
            Self.logResponse(
                provider: config.provider,
                request: request,
                statusCode: http.statusCode,
                data: data,
                strategy: strategy
            )
            guard (200..<300).contains(http.statusCode) else {
                throw AIModelCatalogError.http(http.statusCode)
            }
            let page = try strategy.parse(data, observedAt: observedAt)
            page.models.forEach { descriptors[$0.id] = $0 }
            cursor = page.nextCursor
            if cursor == nil { break }
            if pageNumber == Self.maximumCatalogPages - 1 {
                throw AIModelCatalogError.paginationLimit
            }
        }
        guard !descriptors.isEmpty else { throw AIModelCatalogError.emptyResponse }
        return AIModelCatalogSnapshot(
            profileID: profileID,
            provider: config.provider,
            normalizedEndpoint: AIModelCatalogScope.normalizedEndpoint(config.baseURL),
            models: descriptors.values.sorted { $0.id < $1.id },
            fetchedAt: observedAt
        )
    }

    static func makeRequest(for config: AIConfig) throws -> URLRequest {
        let strategy = AIModelDiscoveryStrategyFactory.make(for: config.provider)
        guard strategy.isAvailable else { throw AIModelCatalogError.unavailable }
        return try makeRequest(
            resolved: AIProviderRegistry.resolve(config),
            strategy: strategy,
            cursor: nil
        )
    }

    static func parseModelIDs(_ data: Data, provider: AIProvider) throws -> [String] {
        let strategy = AIModelDiscoveryStrategyFactory.make(for: provider)
        guard strategy.isAvailable else { throw AIModelCatalogError.unavailable }
        return try strategy.parse(data, observedAt: Date(timeIntervalSince1970: 0))
            .models.filter(\.isWritingCandidate).map(\.id).sorted()
    }

    private static func makeRequest(
        resolved: ResolvedAIProviderConfiguration,
        strategy: any AIModelDiscoveryStrategy,
        cursor: AIModelDiscoveryCursor?
    ) throws -> URLRequest {
        guard var components = catalogComponents(
            generationURL: resolved.endpointURL,
            generationPath: resolved.manifest.endpointPath,
            catalogPath: strategy.catalogPath
        ) else { throw AIModelCatalogError.invalidEndpoint }
        components.queryItems = cursor.map(strategy.queryItems(for:))
            ?? strategy.initialQueryItems()
        guard let url = components.url else { throw AIModelCatalogError.invalidEndpoint }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        switch resolved.manifest.authentication {
        case .bearer:
            request.setValue("Bearer \(resolved.apiKey)", forHTTPHeaderField: "Authorization")
        case .anthropic(let apiVersion):
            request.setValue(resolved.apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        case .googleAPIKey:
            request.setValue(resolved.apiKey, forHTTPHeaderField: "x-goog-api-key")
        }
        return request
    }

    private static func catalogComponents(
        generationURL: URL,
        generationPath: String,
        catalogPath: String
    ) -> URLComponents? {
        guard var components = URLComponents(url: generationURL, resolvingAgainstBaseURL: false)
        else { return nil }
        let suffix = normalizedPath(generationPath)
        let prefix = components.path.hasSuffix(suffix)
            ? String(components.path.dropLast(suffix.count))
            : components.path
        components.path = normalizedPath(prefix) + normalizedPath(catalogPath)
        components.query = nil
        components.fragment = nil
        return components
    }

    private static func normalizedPath(_ path: String) -> String {
        guard !path.isEmpty, path != "/" else { return "" }
        var value = path.hasPrefix("/") ? path : "/" + path
        while value.count > 1, value.hasSuffix("/") { value.removeLast() }
        return value
    }

    private static func logResponse(
        provider: AIProvider,
        request: URLRequest,
        statusCode: Int,
        data: Data,
        strategy: any AIModelDiscoveryStrategy
    ) {
#if DEBUG
        let count = (try? strategy.parse(data, observedAt: .now).models.count) ?? 0
        let host = request.url?.host ?? "unknown"
        let path = request.url?.path ?? "unknown"
        print("[AI-Debug] model-catalog provider=\(provider.rawValue) host=\(host) path=\(path) status=\(statusCode) models=\(count)")
#endif
    }
}
