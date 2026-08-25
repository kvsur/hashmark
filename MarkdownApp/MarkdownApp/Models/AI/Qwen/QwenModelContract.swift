//
//  QwenModelContract.swift
//  MarkdownApp
//
//  Qwen 的日期化精确模型能力与原生路由。动态发现只证明模型可见，不能推断路由或工具能力。
//

import Foundation

nonisolated enum QwenNativeRoute: Equatable {
    case text
    case multimodal
}

nonisolated enum QwenSearchOptionsStyle: Equatable {
    case citations
    case multimodalAgent
}

nonisolated enum QwenModelContract {
    static let reasoningModelIDs = [
        "qwen-plus", "qwen-flash", "qwen-turbo",
        "qwen3.8-max", "qwen3.8-2.4t-a95b", "qwen3.8-27b",
        "qwen3.7-max", "qwen3.7-max-preview",
        "qwen3.7-max-2026-06-08", "qwen3.7-max-2026-05-20",
        "qwen3.7-max-2026-05-17",
        "qwen3.7-plus", "qwen3.7-plus-2026-05-26",
        "qwen3.7-flash", "qwen3.7-flash-2026-07-15",
        "qwen3.6-max-preview",
        "qwen3.6-plus", "qwen3.6-plus-2026-04-02",
        "qwen3.6-flash", "qwen3.6-flash-2026-04-16",
        "qwen3.6-35b-a3b",
        "qwen3.5-plus", "qwen3.5-plus-2026-02-15",
        "qwen3.5-flash", "qwen3.5-flash-2026-02-23",
        "qwen3.5-omni-plus", "qwen3.5-omni-flash"
    ]
    static let reasoningVariantPrefixes = [
        "qwen3.8-max-", "qwen3.8-2.4t-a95b-", "qwen3.8-27b-",
        "qwen3.7-max-", "qwen3.7-plus-", "qwen3.7-flash-",
        "qwen3.6-max-", "qwen3.6-plus-", "qwen3.6-flash-", "qwen3.6-35b-a3b-",
        "qwen3.5-plus-", "qwen3.5-flash-",
        "qwen3.5-omni-plus-", "qwen3.5-omni-flash-"
    ]

    static let searchableModelIDs = [
        "qwen-plus", "qwen-max", "qwen-flash", "qwen-turbo",
        "qwen3.8-max", "qwen3.8-2.4t-a95b", "qwen3.8-27b",
        "qwen3.7-max", "qwen3.7-max-preview",
        "qwen3.7-max-2026-06-08", "qwen3.7-max-2026-05-20",
        "qwen3.7-max-2026-05-17",
        "qwen3.7-plus", "qwen3.7-plus-2026-05-26",
        "qwen3.7-flash", "qwen3.7-flash-2026-07-15",
        "qwen3.6-plus", "qwen3.6-plus-2026-04-02",
        "qwen3.6-flash", "qwen3.6-flash-2026-04-16",
        "qwen3.6-35b-a3b",
        "qwen3.5-plus", "qwen3.5-plus-2026-02-15",
        "qwen3.5-flash", "qwen3.5-flash-2026-02-23",
        "qwen3.5-omni-plus", "qwen3.5-omni-flash"
    ]
    static let searchableVariantPrefixes = [
        "qwen3.8-max-", "qwen3.8-2.4t-a95b-", "qwen3.8-27b-",
        "qwen3.7-max-", "qwen3.7-plus-", "qwen3.7-flash-",
        "qwen3.6-plus-", "qwen3.6-flash-", "qwen3.6-35b-a3b-",
        "qwen3.5-plus-", "qwen3.5-flash-",
        "qwen3.5-omni-plus-", "qwen3.5-omni-flash-"
    ]

    static let multimodalModelIDs = [
        "qwen3.8-max", "qwen3.8-27b",
        "qwen3.7-max-2026-06-08",
        "qwen3.7-plus", "qwen3.7-plus-2026-05-26",
        "qwen3.7-flash", "qwen3.7-flash-2026-07-15",
        "qwen3.6-plus", "qwen3.6-plus-2026-04-02",
        "qwen3.6-flash", "qwen3.6-flash-2026-04-16",
        "qwen3.6-35b-a3b",
        "qwen3.5-plus", "qwen3.5-plus-2026-02-15",
        "qwen3.5-flash", "qwen3.5-flash-2026-02-23",
        "qwen3.5-omni-plus", "qwen3.5-omni-flash"
    ]
    static let multimodalVariantPrefixes = [
        "qwen3.8-max-", "qwen3.8-27b-",
        "qwen3.7-max-2026-06-08-", "qwen3.7-plus-", "qwen3.7-flash-",
        "qwen3.6-plus-", "qwen3.6-flash-", "qwen3.6-35b-a3b-",
        "qwen3.5-plus-", "qwen3.5-flash-",
        "qwen3.5-omni-plus-", "qwen3.5-omni-flash-"
    ]

    // 保留已经过本地上传/提取夹具验证的旧模型；新视觉模型不据此猜测原生 PDF 能力。
    static let documentModelIDs = [
        "qwen3.5-plus", "qwen3.5-flash",
        "qwen3.5-omni-plus", "qwen3.5-omni-flash"
    ]
    static let documentVariantPrefixes = [
        "qwen3.5-plus-", "qwen3.5-flash-",
        "qwen3.5-omni-plus-", "qwen3.5-omni-flash-"
    ]

    private static let multimodalModels = Set(multimodalModelIDs)

    static func route(for model: String) -> QwenNativeRoute {
        let value = normalized(model)
        return multimodalModels.contains(value)
            || multimodalVariantPrefixes.contains { value.hasPrefix($0) }
            ? .multimodal
            : .text
    }

    static func searchOptionsStyle(for model: String) -> QwenSearchOptionsStyle {
        route(for: model) == .multimodal ? .multimodalAgent : .citations
    }

    private static func normalized(_ model: String) -> String {
        model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
