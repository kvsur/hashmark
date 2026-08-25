//
//  AIConfigFormState.swift
//  MarkdownApp
//
//  五家原生 Provider 共用设置页的纯状态派生。Provider 显式选择，能力只由日期化
//  manifest + exact model + 用户偏好决定。
//

import Foundation

nonisolated struct AIConfigCapabilityPreview: Equatable {
    let reasoning: EffectiveCapability?
    let webSearch: EffectiveCapability?
    let imageInput: EffectiveCapability?
    let inlinePDF: EffectiveCapability?
    let files: EffectiveCapability?
    let decisions: [AIModelCapability: AICapabilityDecision]
}

nonisolated enum AIModelFreshnessStatus: Equatable {
    case manifestVerified(date: String)
    case discoveredOnly
    case discoveredStale
    case missingCandidate
    case deprecated
    case shutdown
    case custom
}

nonisolated enum AICapabilityAvailability: Equatable {
    case needsConfiguration
    case available
    case conditional
    case preferenceDisabled
    case providerUnsupported
    case modelNotVerified
    case unverified
    case separateServiceRequired
    case incompatibleCombination

    init(_ capability: EffectiveCapability?) {
        guard let capability else {
            self = .needsConfiguration
            return
        }
        switch capability {
        case .available(.verified): self = .available
        case .available(.conditional): self = .conditional
        case .unavailable(.preferenceDisabled): self = .preferenceDisabled
        case .unavailable(.providerUnsupported): self = .providerUnsupported
        case .unavailable(.modelNotVerified): self = .modelNotVerified
        case .unavailable(.separateServiceRequired): self = .separateServiceRequired
        case .unavailable(.incompatibleCombination): self = .incompatibleCombination
        }
    }

    init(_ decision: AICapabilityDecision?) {
        guard let decision else {
            self = .needsConfiguration
            return
        }
        switch decision.state {
        case .supported: self = .available
        case .unsupported: self = .modelNotVerified
        case .unverified: self = .unverified
        }
    }
}

nonisolated struct AIConfigFormState: Equatable {
    let config: AIConfig
    let catalogSnapshot: AIModelCatalogSnapshot?
    let profileID: UUID
    let evidence: [AICapabilityEvidence]

    init(
        config: AIConfig,
        catalogSnapshot: AIModelCatalogSnapshot? = nil,
        profileID: UUID = AIModelCatalogScope.legacyProfileID,
        evidence: [AICapabilityEvidence] = []
    ) {
        self.config = config
        self.catalogSnapshot = catalogSnapshot
        self.profileID = profileID
        self.evidence = evidence
    }

    var validationIssues: [AIConfigValidationIssue] { config.validationIssues }
    var canSave: Bool { validationIssues.isEmpty }
    var displayedProvider: AIProvider { config.provider }
    var manifest: AIProviderManifest { AIProviderRegistry.manifest(for: config.provider) }
    var endpointPresets: [AIEndpointPreset] { AIEndpointPresets.options(for: config.provider) }
    var documentedModelIDs: [String] { manifest.documentedModelIDs }
    var supportsModelRefresh: Bool { config.provider != .glm }

    var modelFreshness: AIModelFreshnessStatus {
        let model = normalizedModel
        if manifest.capabilities.recognizes(model: model) {
            return .manifestVerified(date: manifest.verifiedAt)
        }
        return .custom
    }

    var hasSearchReasoningConflict: Bool {
        let search = AICapabilityAvailability(capabilityPreview.webSearch)
        guard search == .available || search == .conditional else { return false }
        return AICapabilityAvailability(capabilityPreview.reasoning) == .incompatibleCombination
    }

    var capabilityPreview: AIConfigCapabilityPreview {
        guard let capabilities = previewResolvedProvider?.effectiveCapabilities else {
            return AIConfigCapabilityPreview(
                reasoning: nil,
                webSearch: nil,
                imageInput: nil,
                inlinePDF: nil,
                files: nil,
                decisions: [:]
            )
        }
        let decisions = previewResolvedProvider?.capabilityDecisions(
            profileID: profileID,
            descriptor: selectedDescriptor,
            evidence: evidence
        ) ?? [:]
        return AIConfigCapabilityPreview(
            reasoning: capabilities.displayableReasoning,
            webSearch: capabilities.webSearch,
            imageInput: capabilities.imageInput,
            inlinePDF: Self.bestCapability([
                capabilities.inlinePDF,
                capabilities.fileExtraction
            ]),
            files: Self.combinedFileCapability(capabilities),
            decisions: decisions
        )
    }

    static let providerOptions = AIProvider.allCases

    func modelFreshness(discoveredModelIDs: [String]) -> AIModelFreshnessStatus {
        if case .manifestVerified = modelFreshness { return modelFreshness }
        return discoveredModelIDs.contains(normalizedModel) ? .discoveredOnly : .custom
    }

    func modelFreshness(catalogSnapshot: AIModelCatalogSnapshot?) -> AIModelFreshnessStatus {
        let descriptor = catalogSnapshot?.models.first {
            $0.id.caseInsensitiveCompare(normalizedModel) == .orderedSame
        }
        if descriptor?.lifecycle == .shutdown { return .shutdown }
        if descriptor?.lifecycle == .deprecated { return .deprecated }
        if (descriptor?.missingCount ?? 0) > 0 { return .missingCandidate }
        let manifestLifecycle = AIProviderRegistry.modelPolicy(for: config.provider)
            .lifecycle(model: normalizedModel)
        if manifestLifecycle == .shutdown { return .shutdown }
        if manifestLifecycle == .deprecated { return .deprecated }
        if case .manifestVerified = modelFreshness { return modelFreshness }
        if descriptor != nil {
            return catalogSnapshot?.isStale() == true ? .discoveredStale : .discoveredOnly
        }
        return .custom
    }

    func modelOptions(discoveredModelIDs: [String]) -> [String] {
        let selectedModel = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedModels = selectedModel.isEmpty ? [] : [selectedModel]
        return Array(Set(documentedModelIDs + discoveredModelIDs + selectedModels)).sorted()
    }

    static func applyingProvider(_ provider: AIProvider, to config: AIConfig) -> AIConfig {
        var result = config
        result.provider = provider
        let manifest = AIProviderRegistry.manifest(for: provider)
        result.baseURL = manifest.defaultBaseURL
        result.model = manifest.defaultModel
        return result
    }

    static func normalizedForEditing(_ config: AIConfig) -> AIConfig {
        var result = config
        let manifest = AIProviderRegistry.manifest(for: result.provider)
        if result.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.baseURL = manifest.defaultBaseURL
        }
        if result.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.model = manifest.defaultModel
        }
        return result
    }

    private var previewResolvedProvider: ResolvedAIProviderConfiguration? {
        guard !config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var preview = config
        if preview.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            preview.apiKey = "capability-preview"
        }
        return try? AIProviderRegistry.resolve(preview)
    }

    private var normalizedModel: String {
        config.model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var selectedDescriptor: AIModelDescriptor? {
        catalogSnapshot?.models.first {
            $0.id.caseInsensitiveCompare(normalizedModel) == .orderedSame
        }
    }

    private static func combinedFileCapability(
        _ capabilities: EffectiveProviderCapabilities
    ) -> EffectiveCapability {
        bestCapability([
            capabilities.directFileInput,
            capabilities.uploadedFileReference,
            capabilities.fileExtraction,
            capabilities.fileSearch
        ])
    }

    private static func bestCapability(
        _ candidates: [EffectiveCapability]
    ) -> EffectiveCapability {
        if candidates.contains(.available(.verified)) { return .available(.verified) }
        if candidates.contains(.available(.conditional)) { return .available(.conditional) }
        let reasons = candidates.compactMap { capability -> CapabilityUnavailableReason? in
            if case .unavailable(let reason) = capability { reason } else { nil }
        }
        if reasons.contains(.modelNotVerified) { return .unavailable(.modelNotVerified) }
        if reasons.contains(.incompatibleCombination) { return .unavailable(.incompatibleCombination) }
        if reasons.contains(.separateServiceRequired) { return .unavailable(.separateServiceRequired) }
        return .unavailable(.providerUnsupported)
    }
}
