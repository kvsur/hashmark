//
//  AIEndpointPreset.swift
//  MarkdownApp
//
//  First-party regional endpoint choices. A custom Base URL remains an advanced
//  override for the already-selected Provider and never changes Provider identity.
//

import Foundation

nonisolated struct AIEndpointPreset: Equatable, Identifiable {
    let id: String
    let displayName: String
    let baseURL: String
}

nonisolated enum AIEndpointPresets {
    static func options(for provider: AIProvider) -> [AIEndpointPreset] {
        switch provider {
        case .openAI:
            [preset("global", "Global", "https://api.openai.com/v1")]
        case .anthropic:
            [preset("global", "Global", "https://api.anthropic.com")]
        case .gemini:
            [preset("global", "Global", "https://generativelanguage.googleapis.com")]
        case .kimi:
            [preset("china", "China", "https://api.moonshot.cn/v1")]
        case .glm:
            [preset("china", "China", "https://open.bigmodel.cn")]
        }
    }

    private static func preset(
        _ id: String,
        _ displayName: String,
        _ baseURL: String
    ) -> AIEndpointPreset {
        AIEndpointPreset(id: id, displayName: displayName, baseURL: baseURL)
    }
}
