//
//  ProviderCapabilities.swift
//  MarkdownApp
//
//  日期化 manifest 的能力规则。高级能力只对第一方文档明确列出的模型开启；
//  未知模型仍可保存为基础文本配置，但不会收到猜测的 search/image/file 字段。
//

import Foundation

nonisolated struct ModelCapabilityRule: Equatable {
    let exactIDs: Set<String>
    let variantPrefixes: Set<String>
    let excludedFragments: Set<String>

    init(
        exactIDs: [String],
        variantPrefixes: [String] = [],
        excludedFragments: [String] = []
    ) {
        self.exactIDs = Set(exactIDs.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
        self.variantPrefixes = Set(variantPrefixes.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
        self.excludedFragments = Set(excludedFragments.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
    }

    func matches(_ model: String) -> Bool {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !excludedFragments.contains(where: normalized.contains) else { return false }
        return exactIDs.contains(normalized)
            || variantPrefixes.contains { normalized.hasPrefix($0) }
    }
}

nonisolated enum CapabilitySupport: Equatable {
    case unsupported
    case supported
    case conditional(ModelCapabilityRule)

    func resolve(model: String) -> EffectiveCapability {
        switch self {
        case .unsupported:
            .unavailable(.providerUnsupported)
        case .supported:
            .available(.verified)
        case .conditional(let rule):
            rule.matches(model)
                ? .available(.conditional)
                : .unavailable(.modelNotVerified)
        }
    }
}

nonisolated enum CapabilityConfidence: Equatable {
    case verified
    case conditional
}

nonisolated enum CapabilityUnavailableReason: Equatable {
    case providerUnsupported
    case modelNotVerified
    case separateServiceRequired
    case preferenceDisabled
    case incompatibleCombination
}

nonisolated enum EffectiveCapability: Equatable {
    case available(CapabilityConfidence)
    case unavailable(CapabilityUnavailableReason)

    var isEnabled: Bool {
        if case .available = self { true } else { false }
    }
}

nonisolated struct ProviderCapabilities: Equatable {
    let streaming: CapabilitySupport
    let functionTools: CapabilitySupport
    let displayableReasoning: CapabilitySupport
    let webSearch: CapabilitySupport
    let imageInput: CapabilitySupport
    let inlinePDF: CapabilitySupport
    let directFileInput: CapabilitySupport
    let uploadedFileReference: CapabilitySupport
    let fileExtraction: CapabilitySupport
    let fileSearch: CapabilitySupport

    var documentedModelIDs: [String] {
        let supports = [
            streaming, functionTools, displayableReasoning, webSearch,
            imageInput, inlinePDF, directFileInput, uploadedFileReference,
            fileExtraction, fileSearch
        ]
        let ids = supports.reduce(into: Set<String>()) { result, support in
            if case .conditional(let rule) = support {
                result.formUnion(rule.exactIDs)
            }
        }
        return ids.sorted()
    }

    func recognizes(model: String) -> Bool {
        let supports = [
            streaming, functionTools, displayableReasoning, webSearch,
            imageInput, inlinePDF, directFileInput, uploadedFileReference,
            fileExtraction, fileSearch
        ]
        return supports.contains { support in
            if case .conditional(let rule) = support { return rule.matches(model) }
            return false
        }
    }

    func resolving(
        model: String,
        preferences: AICapabilityPreferences
    ) -> EffectiveProviderCapabilities {
        EffectiveProviderCapabilities(
            streaming: streaming.resolve(model: model),
            functionTools: functionTools.resolve(model: model),
            displayableReasoning: displayableReasoning.resolve(model: model),
            webSearch: preferences.webSearchEnabled
                ? webSearch.resolve(model: model)
                : .unavailable(.preferenceDisabled),
            imageInput: imageInput.resolve(model: model),
            inlinePDF: inlinePDF.resolve(model: model),
            directFileInput: directFileInput.resolve(model: model),
            uploadedFileReference: uploadedFileReference.resolve(model: model),
            fileExtraction: fileExtraction.resolve(model: model),
            fileSearch: fileSearch.resolve(model: model)
        )
    }
}

nonisolated struct EffectiveProviderCapabilities: Equatable {
    var streaming: EffectiveCapability
    var functionTools: EffectiveCapability
    var displayableReasoning: EffectiveCapability
    var webSearch: EffectiveCapability
    var imageInput: EffectiveCapability
    var inlinePDF: EffectiveCapability
    var directFileInput: EffectiveCapability
    var uploadedFileReference: EffectiveCapability
    var fileExtraction: EffectiveCapability
    var fileSearch: EffectiveCapability
}

nonisolated enum AIReasoningEffort: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case low
    case high
    case maximum

    var id: Self { self }
}

nonisolated struct AICapabilityPreferences: Codable, Equatable, Sendable {
    var webSearchEnabled: Bool
    var reasoningEffort: AIReasoningEffort

    init(
        webSearchEnabled: Bool = true,
        reasoningEffort: AIReasoningEffort = .low
    ) {
        self.webSearchEnabled = webSearchEnabled
        self.reasoningEffort = reasoningEffort
    }
}
