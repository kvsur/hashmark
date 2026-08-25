//
//  AICapabilityVerificationStore.swift
//  MarkdownApp
//
//  版本化本地执行证据。auth/网络/限流/5xx/取消均保持 inconclusive。
//

import Foundation

nonisolated enum AICapabilityFailureKind: Equatable, Sendable {
    case explicitUnsupported(reasonCode: String)
    case authentication
    case rateLimited
    case network
    case server
    case cancelled
    case invalidRequest
    case unknown
}

nonisolated enum AICapabilityFailurePolicy {
    static func classifyHTTP(status: Int, body: String?) -> AICapabilityFailureKind {
        if status == 401 || status == 403 { return .authentication }
        if status == 429 { return .rateLimited }
        if status >= 500 { return .server }
        if [400, 404, 422].contains(status), explicitlyRejectsCapability(body) {
            return .explicitUnsupported(reasonCode: "provider_explicitly_unsupported")
        }
        return .invalidRequest
    }

    private static func explicitlyRejectsCapability(_ body: String?) -> Bool {
        guard let body else { return false }
        let value = body.lowercased()
        let capabilityMarkers = [
            "web_search", "web search", "google_search", "web-search"
        ]
        let rejectionMarkers = [
            "not supported", "unsupported", "unknown tool", "unrecognized tool",
            "invalid tool", "does not support", "not available for this model"
        ]
        return capabilityMarkers.contains(where: value.contains)
            && rejectionMarkers.contains(where: value.contains)
    }
}

nonisolated struct AICapabilityVerificationStore {
    private struct Storage: Codable {
        var version = 1
        var evidence: [AICapabilityEvidence] = []
    }

    static let evidenceTTL: TimeInterval = 30 * 24 * 60 * 60
    private let defaults: UserDefaults
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "AICapabilityVerification.v1"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func allEvidence(now: Date = .now) -> [AICapabilityEvidence] {
        load().evidence.filter { $0.expiresAt > now }
    }

    @discardableResult
    func recordSuccess(
        profileID: UUID,
        provider: AIProvider,
        endpoint: String,
        model: String,
        capability: AIModelCapability,
        observedAt: Date = .now,
        reasonCode: String = "request_succeeded"
    ) -> AICapabilityEvidence {
        record(
            profileID: profileID,
            provider: provider,
            endpoint: endpoint,
            model: model,
            capability: capability,
            outcome: .supported,
            observedAt: observedAt,
            reasonCode: reasonCode
        )
    }

    @discardableResult
    func recordFailure(
        profileID: UUID,
        provider: AIProvider,
        endpoint: String,
        model: String,
        capability: AIModelCapability,
        failure: AICapabilityFailureKind,
        observedAt: Date = .now
    ) -> AICapabilityEvidence {
        let outcome: AICapabilityEvidenceOutcome
        let reason: String
        switch failure {
        case .explicitUnsupported(let reasonCode):
            outcome = .unsupported
            reason = reasonCode
        case .authentication:
            outcome = .inconclusive
            reason = "authentication"
        case .rateLimited:
            outcome = .inconclusive
            reason = "rate_limited"
        case .network:
            outcome = .inconclusive
            reason = "network"
        case .server:
            outcome = .inconclusive
            reason = "server"
        case .cancelled:
            outcome = .inconclusive
            reason = "cancelled"
        case .invalidRequest:
            outcome = .inconclusive
            reason = "invalid_request"
        case .unknown:
            outcome = .inconclusive
            reason = "unknown"
        }
        return record(
            profileID: profileID,
            provider: provider,
            endpoint: endpoint,
            model: model,
            capability: capability,
            outcome: outcome,
            observedAt: observedAt,
            reasonCode: reason
        )
    }

    func invalidate(profileID: UUID) {
        var storage = load()
        storage.evidence.removeAll { $0.profileID == profileID }
        persist(storage)
    }

    func prune(now: Date = .now) {
        var storage = load()
        storage.evidence.removeAll { $0.expiresAt <= now }
        persist(storage)
    }

    private func record(
        profileID: UUID,
        provider: AIProvider,
        endpoint: String,
        model: String,
        capability: AIModelCapability,
        outcome: AICapabilityEvidenceOutcome,
        observedAt: Date,
        reasonCode: String
    ) -> AICapabilityEvidence {
        let value = AICapabilityEvidence(
            id: UUID(),
            profileID: profileID,
            provider: provider,
            normalizedEndpoint: AIModelCatalogScope.normalizedEndpoint(endpoint),
            model: model.trimmingCharacters(in: .whitespacesAndNewlines),
            capability: capability,
            outcome: outcome,
            observedAt: observedAt,
            expiresAt: observedAt.addingTimeInterval(Self.evidenceTTL),
            manifestVersion: AIProviderRegistry.manifestContentVersion,
            protocolVersion: AIProviderRegistry.protocolEvidenceVersion,
            reasonCode: reasonCode
        )
        var storage = load()
        storage.evidence.append(value)
        storage.evidence = Array(storage.evidence.suffix(500))
        persist(storage)
        return value
    }

    private func load() -> Storage {
        guard let data = defaults.data(forKey: storageKey),
              let storage = try? JSONDecoder().decode(Storage.self, from: data)
        else { return Storage() }
        return storage
    }

    private func persist(_ storage: Storage) {
        guard let data = try? JSONEncoder().encode(storage) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
