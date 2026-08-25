//
//  KimiModelContract.swift
//  MarkdownApp
//
//  Kimi reasoning wire strategy helper。型号规则来自 Bundle Manifest。
//

import Foundation

nonisolated enum KimiReasoningStyle: Equatable {
    case thinkingToggle
    case reasoningEffort
}

nonisolated enum KimiModelContract {
    static func reasoningStyle(for model: String) -> KimiReasoningStyle? {
        switch AIModelManifestRepository.shared.provider(.kimi)?
            .strategyID(key: "reasoningStyle", model: model) {
        case "kimiReasoningEffort": .reasoningEffort
        case "kimiThinkingToggle": .thinkingToggle
        default: nil
        }
    }
}
