//
//  AICapabilityResolver.swift
//  MarkdownApp
//
//  固定五层优先级：Provider metadata > exact Manifest > family Manifest
//  > verified local result > conservative unverified fallback。
//

import Foundation

nonisolated struct AICapabilityResolutionContext: Sendable {
    let profileID: UUID
    let provider: AIProvider
    let normalizedEndpoint: String
    let model: String
    let descriptor: AIModelDescriptor?
    let providerMetadataSignals: [AIModelCapability: Bool]
    let providerMetadataObservedAt: Date?
    let evidence: [AICapabilityEvidence]
    let manifestVersion: String
    let protocolVersion: String
    let now: Date

    init(
        profileID: UUID = AIModelCatalogScope.legacyProfileID,
        provider: AIProvider,
        endpoint: String,
        model: String,
        descriptor: AIModelDescriptor? = nil,
        providerMetadataSignals: [AIModelCapability: Bool]? = nil,
        providerMetadataObservedAt: Date? = nil,
        evidence: [AICapabilityEvidence] = [],
        manifestVersion: String = AIProviderRegistry.manifestContentVersion,
        protocolVersion: String = AIProviderRegistry.protocolEvidenceVersion,
        now: Date = .now
    ) {
        self.profileID = profileID
        self.provider = provider
        self.normalizedEndpoint = AIModelCatalogScope.normalizedEndpoint(endpoint)
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.descriptor = descriptor
        self.providerMetadataSignals = providerMetadataSignals
            ?? descriptor?.metadata.capabilitySignals
            ?? [:]
        self.providerMetadataObservedAt = providerMetadataObservedAt
            ?? descriptor?.lastSeenAt
        self.evidence = evidence
        self.manifestVersion = manifestVersion
        self.protocolVersion = protocolVersion
        self.now = now
    }
}

nonisolated enum AICapabilityResolver {
    static let advancedCapabilities: [AIModelCapability] = [
        .imageInput, .pdfInput, .genericFileInput, .reasoning, .nativeWebSearch
    ]

    static func resolveAll(
        _ context: AICapabilityResolutionContext
    ) -> [AIModelCapability: AICapabilityDecision] {
        Dictionary(uniqueKeysWithValues: advancedCapabilities.map {
            ($0, resolve($0, context: context))
        })
    }

    static func resolve(
        _ capability: AIModelCapability,
        context: AICapabilityResolutionContext
    ) -> AICapabilityDecision {
        guard let policy = AIModelManifestRepository.shared.provider(context.provider) else {
            return fallback(capability, context: context, reason: "provider manifest missing")
        }

        if let value = context.providerMetadataSignals[capability] {
            return decision(
                capability,
                state: value ? .supported : .unsupported,
                source: .providerMetadata,
                confidence: .high,
                reason: "provider models API returned an explicit capability value",
                observedAt: context.providerMetadataObservedAt,
                context: context
            )
        }

        if let value = policy.exactState(for: capability, model: context.model)
            ?? policy.providerState(for: capability) {
            return decision(
                capability,
                state: value == .supported ? .supported : .unsupported,
                source: .exactManifest,
                confidence: .high,
                reason: "versioned Manifest exact/provider rule",
                observedAt: nil,
                context: context
            )
        }

        if let value = policy.familyState(for: capability, model: context.model) {
            return decision(
                capability,
                state: value == .supported ? .supported : .unsupported,
                source: .familyManifest,
                confidence: .medium,
                reason: "versioned Manifest family rule",
                observedAt: nil,
                context: context
            )
        }

        if let evidence = newestUsableEvidence(capability, context: context) {
            return decision(
                capability,
                state: evidence.outcome == .supported ? .supported : .unsupported,
                source: .runtimeVerification,
                confidence: .high,
                reason: evidence.reasonCode,
                observedAt: evidence.observedAt,
                context: context
            )
        }

        return fallback(capability, context: context, reason: "capability has not been verified")
    }

    private static func newestUsableEvidence(
        _ capability: AIModelCapability,
        context: AICapabilityResolutionContext
    ) -> AICapabilityEvidence? {
        context.evidence.filter {
            $0.profileID == context.profileID
                && $0.provider == context.provider
                && $0.normalizedEndpoint == context.normalizedEndpoint
                && $0.model.caseInsensitiveCompare(context.model) == .orderedSame
                && $0.capability == capability
                && $0.manifestVersion == context.manifestVersion
                && $0.protocolVersion == context.protocolVersion
                && $0.expiresAt > context.now
                && $0.outcome != .inconclusive
        }.max { $0.observedAt < $1.observedAt }
    }

    private static func fallback(
        _ capability: AIModelCapability,
        context: AICapabilityResolutionContext,
        reason: String
    ) -> AICapabilityDecision {
        decision(
            capability,
            state: .unverified,
            source: .conservativeFallback,
            confidence: .low,
            reason: reason,
            observedAt: nil,
            context: context,
            trialEligible: capability == .nativeWebSearch
        )
    }

    private static func decision(
        _ capability: AIModelCapability,
        state: AICapabilityState,
        source: AICapabilitySource,
        confidence: AICapabilityDecisionConfidence,
        reason: String,
        observedAt: Date?,
        context: AICapabilityResolutionContext,
        trialEligible: Bool = false
    ) -> AICapabilityDecision {
        AICapabilityDecision(
            capability: capability,
            state: state,
            source: source,
            confidence: confidence,
            reason: reason,
            observedAt: observedAt,
            manifestVersion: context.manifestVersion,
            protocolVersion: context.protocolVersion,
            trialEligible: trialEligible
        )
    }
}

nonisolated extension ResolvedAIProviderConfiguration {
    func capabilityDecisions(
        profileID: UUID? = nil,
        descriptor: AIModelDescriptor? = nil,
        evidence: [AICapabilityEvidence]? = nil,
        now: Date = .now
    ) -> [AIModelCapability: AICapabilityDecision] {
        let effectiveProfileID = profileID ?? self.profileID
        let runtimeEvidence = evidence ?? (
            effectiveProfileID == AIModelCatalogScope.legacyProfileID
                ? []
                : AICapabilityVerificationStore().allEvidence(now: now)
        )
        return AICapabilityResolver.resolveAll(AICapabilityResolutionContext(
            profileID: effectiveProfileID,
            provider: provider,
            endpoint: baseURL,
            model: model,
            descriptor: descriptor,
            providerMetadataSignals: descriptor == nil ? providerCapabilitySignals : nil,
            providerMetadataObservedAt: descriptor == nil ? providerMetadataObservedAt : nil,
            evidence: runtimeEvidence,
            now: now
        ))
    }

    func capabilityDecision(
        for capability: AIModelCapability,
        evidence: [AICapabilityEvidence]? = nil,
        now: Date = .now
    ) -> AICapabilityDecision {
        capabilityDecisions(evidence: evidence, now: now)[capability]!
    }

    var usesNativeWebSearch: Bool {
        webSearchRequested
            && capabilityDecision(for: .nativeWebSearch).allowsTrialRequest
    }

    func allowsKnownSafeRequest(_ capability: AIModelCapability) -> Bool {
        supportsKnownSafeRequest(capability)
    }

    func supportsKnownSafeRequest(_ capability: AIModelCapability) -> Bool {
        capabilityDecision(for: capability).allowsKnownSafeRequest
    }
}
