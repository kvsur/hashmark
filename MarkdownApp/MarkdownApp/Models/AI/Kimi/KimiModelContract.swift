//
//  KimiModelContract.swift
//  MarkdownApp
//
//  Kimi 模型级多模态/推理契约。Files 内容提取是 Provider 级服务，
//  不在这里重复绑定到聊天模型白名单。
//

import Foundation

nonisolated enum KimiReasoningStyle: Equatable {
    case thinkingToggle
    case reasoningEffort
}

nonisolated enum KimiModelContract {
    static let reasoningModelIDs = ["kimi-k3", "kimi-k2.6", "kimi-k2.5"]
    static let visualModelIDs = reasoningModelIDs

    static let reasoningVariantPrefixes = ["kimi-k3-", "kimi-k2.6-", "kimi-k2.5-"]
    static let visualVariantPrefixes = reasoningVariantPrefixes

    static func reasoningStyle(for model: String) -> KimiReasoningStyle? {
        let value = normalized(model)
        if value == "kimi-k3" || value.hasPrefix("kimi-k3-") {
            return .reasoningEffort
        }
        if ["kimi-k2.6", "kimi-k2.5"].contains(value)
            || value.hasPrefix("kimi-k2.6-")
            || value.hasPrefix("kimi-k2.5-") {
            return .thinkingToggle
        }
        return nil
    }

    private static func normalized(_ model: String) -> String {
        model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
