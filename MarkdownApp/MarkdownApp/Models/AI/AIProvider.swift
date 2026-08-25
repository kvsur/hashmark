//
//  AIProvider.swift
//  MarkdownApp
//
//  产品正式支持的第一方 AIGC 服务。Provider 身份直接决定原生 wire contract，
//  不再经过 OpenAI/Anthropic 协议枚举、域名猜测或兼容层。
//

import Foundation

nonisolated enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case openAI
    case anthropic
    case gemini
    case qwen
    case kimi
    case glm

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .gemini: "Google Gemini"
        case .qwen: "Alibaba Cloud Qwen"
        case .kimi: "Moonshot Kimi"
        case .glm: "Zhipu GLM"
        }
    }

    static let officiallySupported = allCases
}

