//
//  GeminiModelContract.swift
//  MarkdownApp
//
//  Gemini Interactions 的日期化模型能力。生成模型、File Search 与版本快照
//  分开建模，避免模型列表中的 embedding/image/live 资源进入写作配置。
//

import Foundation

nonisolated enum GeminiModelContract {
    static let interactionModelIDs = [
        "gemini-3.7-flash", "gemini-3.6-flash",
        "gemini-3.5-flash", "gemini-3.5-flash-lite",
        "gemini-3.1-pro-preview", "gemini-3.1-flash-lite",
        "gemini-3-flash-preview",
        "gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.5-flash-lite"
    ]

    static let interactionVariantPrefixes = [
        "gemini-3.7-flash-", "gemini-3.6-flash-",
        "gemini-3.5-flash-", "gemini-3.5-flash-lite-",
        "gemini-3.1-pro-preview-", "gemini-3.1-flash-lite-",
        "gemini-3-flash-preview-",
        "gemini-2.5-pro-", "gemini-2.5-flash-", "gemini-2.5-flash-lite-"
    ]
    static let interactionFamilyPrefixes = ["gemini-3.", "gemini-2.5-"]
    static let nonWritingModelFragments = [
        "-image", "-live", "-tts", "embedding", "robotics", "omni"
    ]

    static let reasoningModelIDs = interactionModelIDs
    static let searchModelIDs = interactionModelIDs
    static let multimodalModelIDs = interactionModelIDs

    // Google 的 File Search 支持表比通用图片/PDF输入更窄，不能复用一张模型表。
    static let fileSearchModelIDs = [
        "gemini-3.7-flash", "gemini-3.6-flash",
        "gemini-3.5-flash", "gemini-3.5-flash-lite",
        "gemini-3.1-pro-preview", "gemini-3.1-flash-lite",
        "gemini-3-flash-preview"
    ]
    static let fileSearchVariantPrefixes = [
        "gemini-3.7-flash-", "gemini-3.6-flash-",
        "gemini-3.5-flash-", "gemini-3.5-flash-lite-",
        "gemini-3.1-pro-preview-", "gemini-3.1-flash-lite-",
        "gemini-3-flash-preview-"
    ]

    static func supportsInteractions(_ model: String) -> Bool {
        let value = normalized(model)
        guard !nonWritingModelFragments.contains(where: value.contains) else { return false }
        return interactionModelIDs.contains(value)
            || interactionFamilyPrefixes.contains { value.hasPrefix($0) }
    }

    private static func normalized(_ model: String) -> String {
        model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
