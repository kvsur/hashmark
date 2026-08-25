//
//  AIModelDiscoveryStrategy.swift
//  MarkdownApp
//
//  Models API 只共享安全 transport/pagination 骨架；各 Provider 独立解析 wire schema。
//

import Foundation

nonisolated struct AIModelDiscoveryCursor: Equatable, Sendable {
    let name: String
    let value: String
}

nonisolated struct AIModelDiscoveryPage: Equatable, Sendable {
    let models: [AIModelDescriptor]
    let nextCursor: AIModelDiscoveryCursor?
}

nonisolated protocol AIModelDiscoveryStrategy: Sendable {
    var provider: AIProvider { get }
    var isAvailable: Bool { get }
    var catalogPath: String { get }
    func initialQueryItems() -> [URLQueryItem]
    func queryItems(for cursor: AIModelDiscoveryCursor) -> [URLQueryItem]
    func parse(_ data: Data, observedAt: Date) throws -> AIModelDiscoveryPage
}

nonisolated extension AIModelDiscoveryStrategy {
    var isAvailable: Bool { true }
    func initialQueryItems() -> [URLQueryItem] { [] }
    func queryItems(for cursor: AIModelDiscoveryCursor) -> [URLQueryItem] {
        [URLQueryItem(name: cursor.name, value: cursor.value)]
    }
}

nonisolated enum AIModelDiscoveryStrategyFactory {
    static func make(for provider: AIProvider) -> any AIModelDiscoveryStrategy {
        switch provider {
        case .openAI: OpenAIModelDiscoveryStrategy()
        case .anthropic: AnthropicModelDiscoveryStrategy()
        case .gemini: GeminiModelDiscoveryStrategy()
        case .kimi: KimiModelDiscoveryStrategy()
        case .glm: GLMModelDiscoveryStrategy()
        }
    }
}

nonisolated enum AIModelDiscoveryParsing {
    static func object(_ data: Data) throws -> [String: Any] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw AIModelCatalogError.invalidResponse }
        return root
    }

    static func string(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    static func date(_ value: Any?) -> Date? {
        if let seconds = integer(value) { return Date(timeIntervalSince1970: TimeInterval(seconds)) }
        guard let value = string(value) else { return nil }
        if let date = ISO8601DateFormatter().date(from: value) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    static func explicitBool(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? [String: Any] {
            return explicitBool(value["supported"] ?? value["enabled"] ?? value["available"])
        }
        return nil
    }

    static func descriptor(
        id: String,
        displayName: String? = nil,
        metadata: AIModelProviderMetadata = AIModelProviderMetadata(),
        lifecycle: AIModelLifecycle = .active,
        observedAt: Date
    ) -> AIModelDescriptor {
        AIModelDescriptor(
            id: id,
            displayName: displayName,
            metadata: metadata,
            lifecycle: lifecycle,
            source: .providerAPI,
            firstSeenAt: observedAt,
            lastSeenAt: observedAt,
            missingCount: 0
        )
    }
}

