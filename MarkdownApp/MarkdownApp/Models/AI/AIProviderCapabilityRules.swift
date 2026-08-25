//
//  AIProviderCapabilityRules.swift
//  MarkdownApp
//
//  六家 Provider 的模型能力规则装配。Provider 私有模型清单留在各自 Contract，
//  此处只把它们映射到通用的精确 ID、版本家族和排除规则。
//

import Foundation

nonisolated enum AIProviderCapabilityRules {
    static let openAI = rule(
        ["gpt-5.6", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"],
        variantPrefixes: ["gpt-5."]
    )

    static let anthropicReasoning = rule([
        "claude-fable-5", "claude-mythos-5",
        "claude-opus-4-8", "claude-opus-4-7", "claude-opus-4-6",
        "claude-sonnet-5", "claude-sonnet-4-6"
    ], variantPrefixes: [
        "claude-fable-5-", "claude-mythos-5-",
        "claude-opus-4-8-", "claude-opus-4-7-", "claude-opus-4-6-",
        "claude-sonnet-5-", "claude-sonnet-4-6-"
    ])

    // 第一方文档声明所有 active Claude 均支持视觉/PDF；模型列表已限定 claude-*。
    static let anthropicInput = rule([], variantPrefixes: ["claude-"])

    static let anthropicForcedSearch = rule([
        // Mythos Preview 不支持 forced tool choice，不能满足“搜索开启即执行”。
        "claude-fable-5",
        "claude-opus-4-8", "claude-opus-4-7", "claude-opus-4-6",
        "claude-sonnet-5", "claude-sonnet-4-6"
    ], variantPrefixes: [
        "claude-fable-5-",
        "claude-opus-4-8-", "claude-opus-4-7-", "claude-opus-4-6-",
        "claude-sonnet-5-", "claude-sonnet-4-6-"
    ])

    static let geminiReasoning = geminiRule(GeminiModelContract.reasoningModelIDs)
    static let geminiSearch = geminiRule(GeminiModelContract.searchModelIDs)
    static let geminiMultimodal = geminiRule(GeminiModelContract.multimodalModelIDs)
    static let geminiFileSearch = rule(
        GeminiModelContract.fileSearchModelIDs,
        variantPrefixes: GeminiModelContract.fileSearchVariantPrefixes
    )

    static let qwenReasoning = rule(
        QwenModelContract.reasoningModelIDs,
        variantPrefixes: QwenModelContract.reasoningVariantPrefixes
    )
    static let qwenSearch = rule(
        QwenModelContract.searchableModelIDs,
        variantPrefixes: QwenModelContract.searchableVariantPrefixes
    )
    static let qwenMultimodal = rule(
        QwenModelContract.multimodalModelIDs,
        variantPrefixes: QwenModelContract.multimodalVariantPrefixes
    )
    static let qwenDocument = rule(
        QwenModelContract.documentModelIDs,
        variantPrefixes: QwenModelContract.documentVariantPrefixes
    )

    static let kimiReasoning = rule(
        KimiModelContract.reasoningModelIDs,
        variantPrefixes: KimiModelContract.reasoningVariantPrefixes
    )
    static let kimiVisual = rule(
        KimiModelContract.visualModelIDs,
        variantPrefixes: KimiModelContract.visualVariantPrefixes
    )

    static let glmText = rule(
        GLMModelContract.textModelIDs,
        variantPrefixes: GLMModelContract.textVariantPrefixes
    )
    static let glmVision = rule(
        GLMModelContract.visualModelIDs,
        variantPrefixes: GLMModelContract.visualVariantPrefixes
    )
    static let glmReasoning = rule(
        GLMModelContract.reasoningModelIDs,
        variantPrefixes: GLMModelContract.reasoningVariantPrefixes
    )

    private static func geminiRule(_ ids: [String]) -> ModelCapabilityRule {
        rule(
            ids,
            variantPrefixes: GeminiModelContract.interactionFamilyPrefixes,
            excludedFragments: GeminiModelContract.nonWritingModelFragments
        )
    }

    private static func rule(
        _ ids: [String],
        variantPrefixes: [String] = [],
        excludedFragments: [String] = []
    ) -> ModelCapabilityRule {
        ModelCapabilityRule(
            exactIDs: ids,
            variantPrefixes: variantPrefixes,
            excludedFragments: excludedFragments
        )
    }
}
