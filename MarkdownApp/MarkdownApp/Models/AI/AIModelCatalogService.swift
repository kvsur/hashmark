//
//  AIModelCatalogService.swift
//  MarkdownApp
//
//  Optional first-party model discovery for Settings. Results describe account
//  or regional catalog visibility; capability authority stays in the dated local manifest.
//

import Foundation

nonisolated struct AIModelCatalogSnapshot: Equatable {
    let provider: AIProvider
    let modelIDs: [String]
    let fetchedAt: Date
}

nonisolated enum AIModelCatalogError: Error, Equatable {
    case unavailable
    case invalidEndpoint
    case invalidResponse
    case http(Int)
}

final class AIModelCatalogService {
    private static let maximumCatalogPages = 20
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(for config: AIConfig) async throws -> AIModelCatalogSnapshot {
        var request = try Self.makeRequest(for: config)
        var modelIDs = Set<String>()
        var fetchedPages = 0

        while true {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AIModelCatalogError.invalidResponse
            }
            Self.logResponse(
                provider: config.provider,
                request: request,
                statusCode: http.statusCode,
                data: data
            )
            guard (200..<300).contains(http.statusCode) else {
                throw AIModelCatalogError.http(http.statusCode)
            }
            modelIDs.formUnion(try Self.parseModelIDs(data, provider: config.provider))
            fetchedPages += 1

            guard config.provider == .qwen,
                  fetchedPages < Self.maximumCatalogPages,
                  let page = try Self.qwenPage(from: data),
                  page.number * page.size < page.total
            else { break }
            request = try Self.settingQwenPage(page.number + 1, on: request)
        }

        return AIModelCatalogSnapshot(
            provider: config.provider,
            modelIDs: modelIDs.sorted(),
            fetchedAt: .now
        )
    }

    static func makeRequest(for config: AIConfig) throws -> URLRequest {
        guard config.provider != .glm else { throw AIModelCatalogError.unavailable }
        let resolved = try AIProviderRegistry.resolve(config)
        let catalogPath = switch config.provider {
        case .openAI, .anthropic, .kimi: "/v1/models"
        case .gemini: "/v1beta/models"
        case .qwen:
            qwenUsesLegacyChinaCatalog(resolved.endpointURL)
                ? "/api/v1/models/permissions"
                : "/api/v1/models"
        case .glm: throw AIModelCatalogError.unavailable
        }
        guard var url = catalogURL(
            generationURL: resolved.endpointURL,
            generationPath: resolved.manifest.endpointPath,
            catalogPath: catalogPath
        ) else { throw AIModelCatalogError.invalidEndpoint }

        if config.provider == .qwen {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if components?.path.hasSuffix("/models/permissions") == true {
                components?.queryItems = [
                    URLQueryItem(name: "authorization_scope", value: "AUTHORIZED"),
                    URLQueryItem(name: "action", value: "INFERENCE"),
                    URLQueryItem(name: "page_no", value: "1"),
                    URLQueryItem(name: "page_size", value: "200")
                ]
            } else {
                components?.queryItems = [
                    URLQueryItem(name: "providers", value: "qwen"),
                    URLQueryItem(name: "capabilities", value: "TG"),
                    URLQueryItem(name: "supports", value: "inference"),
                    URLQueryItem(name: "page_no", value: "1"),
                    URLQueryItem(name: "page_size", value: "100")
                ]
            }
            guard let queryURL = components?.url else { throw AIModelCatalogError.invalidEndpoint }
            url = queryURL
        }

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

    static func parseModelIDs(_ data: Data, provider: AIProvider) throws -> [String] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIModelCatalogError.invalidResponse
        }
        if provider == .qwen, root["success"] as? Bool == false {
            throw AIModelCatalogError.invalidResponse
        }
        let objects: [[String: Any]] = switch provider {
        case .openAI, .anthropic, .kimi:
            root["data"] as? [[String: Any]] ?? []
        case .gemini:
            root["models"] as? [[String: Any]] ?? []
        case .qwen:
            qwenModelObjects(root)
        case .glm:
            throw AIModelCatalogError.unavailable
        }

        let values = objects.compactMap { object -> String? in
            switch provider {
            case .gemini:
                if let base = object["baseModelId"] as? String { return base }
                return (object["name"] as? String)?.replacingOccurrences(of: "models/", with: "")
            case .qwen:
                return object["model_id"] as? String
                    ?? object["model"] as? String
                    ?? object["id"] as? String
                    ?? object["name"] as? String
            default:
                return object["id"] as? String
            }
        }
        let filtered = values.filter { isUsefulModelID($0, provider: provider) }
        return Array(Set(filtered)).sorted()
    }

    private static func catalogURL(
        generationURL: URL,
        generationPath: String,
        catalogPath: String
    ) -> URL? {
        guard var components = URLComponents(url: generationURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let currentPath = components.path
        let suffix = normalizedPath(generationPath)
        let prefix = currentPath.hasSuffix(suffix)
            ? String(currentPath.dropLast(suffix.count))
            : currentPath
        components.path = normalizedPath(prefix) + normalizedPath(catalogPath)
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func qwenUsesLegacyChinaCatalog(_ generationURL: URL) -> Bool {
        generationURL.host?.lowercased() == "dashscope.aliyuncs.com"
    }

    private static func settingQwenPage(_ page: Int, on request: URLRequest) throws -> URLRequest {
        guard let url = request.url,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { throw AIModelCatalogError.invalidEndpoint }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == "page_no" }
        items.append(URLQueryItem(name: "page_no", value: String(page)))
        components.queryItems = items
        guard let updatedURL = components.url else { throw AIModelCatalogError.invalidEndpoint }
        var updated = request
        updated.url = updatedURL
        return updated
    }

    private static func qwenPage(from data: Data) throws -> (number: Int, size: Int, total: Int)? {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = root["output"] as? [String: Any]
        else { return nil }
        guard let number = integer(output["page_no"]),
              let size = integer(output["page_size"]),
              let total = integer(output["total"]),
              number > 0,
              size > 0,
              total >= 0
        else { return nil }
        return (number, size, total)
    }

    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func logResponse(
        provider: AIProvider,
        request: URLRequest,
        statusCode: Int,
        data: Data
    ) {
#if DEBUG
        let count = (try? parseModelIDs(data, provider: provider).count) ?? 0
        let host = request.url?.host ?? "unknown"
        let path = request.url?.path ?? "unknown"
        let page = request.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "page_no" })?.value
        } ?? "-"
        print("[AI-Debug] model-catalog provider=\(provider.rawValue) host=\(host) path=\(path) status=\(statusCode) page=\(page) models=\(count)")
#endif
    }

    private static func qwenModelObjects(_ root: [String: Any]) -> [[String: Any]] {
        if let data = root["data"] as? [[String: Any]] { return data }
        if let models = root["models"] as? [[String: Any]] { return models }
        if let output = root["output"] as? [String: Any] {
            return output["models"] as? [[String: Any]]
                ?? output["data"] as? [[String: Any]]
                ?? output["permissions"] as? [[String: Any]]
                ?? []
        }
        return []
    }

    private static func isUsefulModelID(_ model: String, provider: AIProvider) -> Bool {
        let value = model.lowercased()
        return switch provider {
        case .openAI:
            value.hasPrefix("gpt-") || value.hasPrefix("o1")
                || value.hasPrefix("o3") || value.hasPrefix("o4")
        case .anthropic: value.hasPrefix("claude-")
        case .gemini: GeminiModelContract.supportsInteractions(value)
        case .qwen: value.hasPrefix("qwen")
        case .kimi: value.hasPrefix("kimi-") || value.hasPrefix("moonshot-")
        case .glm: false
        }
    }

    private static func normalizedPath(_ path: String) -> String {
        guard !path.isEmpty, path != "/" else { return "" }
        var value = path.hasPrefix("/") ? path : "/" + path
        while value.count > 1, value.hasSuffix("/") { value.removeLast() }
        return value
    }
}
