//
//  GLMModelContract.swift
//  MarkdownApp
//
//  GLM 文本与视觉模型契约。模型名带 V 才进入多模态请求路径；
//  日期快照继承已验证基座的路由，未知大版本仍保持关闭。
//

import Foundation

nonisolated enum GLMModelContract {
    static let textModelIDs = [
        "glm-5.3", "glm-5.2", "glm-5.1", "glm-5-turbo", "glm-5",
        "glm-4.7", "glm-4.6", "glm-4.5-air", "glm-4.5-flash"
    ]
    static let textVariantPrefixes = [
        "glm-5.3-", "glm-5.2-", "glm-5.1-", "glm-5-turbo-",
        "glm-4.7-", "glm-4.6-", "glm-4.5-air-", "glm-4.5-flash-"
    ]

    static let visualModelIDs = ["glm-5v-turbo", "glm-4.6v", "glm-4.6v-flash"]
    static let visualVariantPrefixes = [
        "glm-5v-turbo-", "glm-4.6v-flash-", "glm-4.6v-"
    ]

    static let reasoningModelIDs = textModelIDs + visualModelIDs
    static let reasoningVariantPrefixes = textVariantPrefixes + visualVariantPrefixes
}
