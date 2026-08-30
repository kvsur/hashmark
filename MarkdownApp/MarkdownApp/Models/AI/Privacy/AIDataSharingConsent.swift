//
//  AIDataSharingConsent.swift
//  MarkdownApp
//
//  第三方 AI 数据分享授权按 Provider + Endpoint 隔离。接收方变化时旧授权不会复用。
//

import Foundation

nonisolated struct AIDataSharingRecipient: Equatable, Sendable {
    static let consentVersion = 1

    let provider: AIProvider
    let endpoint: String

    init(config: AIConfig) {
        provider = config.provider
        endpoint = Self.normalizedEndpoint(config.baseURL)
    }

    var scopeID: String {
        "v\(Self.consentVersion)|\(provider.rawValue)|\(endpoint)"
    }

    var displayEndpoint: String {
        endpoint.isEmpty ? configFallback : endpoint
    }

    private var configFallback: String {
        AIProviderRegistry.manifest(for: provider).defaultBaseURL
    }

    private static func normalizedEndpoint(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed) else {
            return trimmed.lowercased()
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        while components.path.count > 1, components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        return components.string ?? trimmed.lowercased()
    }
}

nonisolated struct AIDataSharingConsentStore {
    static let defaultStorageKey = "AIDataSharingConsentScopes.v1"

    private let defaults: UserDefaults
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = Self.defaultStorageKey
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func hasConsent(for config: AIConfig) -> Bool {
        scopes.contains(AIDataSharingRecipient(config: config).scopeID)
    }

    func grant(for config: AIConfig) {
        var updated = scopes
        updated.insert(AIDataSharingRecipient(config: config).scopeID)
        persist(updated)
    }

    func revoke(for config: AIConfig) {
        var updated = scopes
        updated.remove(AIDataSharingRecipient(config: config).scopeID)
        persist(updated)
    }

    func revokeAll() {
        defaults.removeObject(forKey: storageKey)
    }

    private var scopes: Set<String> {
        Set(defaults.stringArray(forKey: storageKey) ?? [])
    }

    private func persist(_ value: Set<String>) {
        defaults.set(value.sorted(), forKey: storageKey)
    }
}
