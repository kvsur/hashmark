//
//  GeminiModelContract.swift
//  MarkdownApp
//
//  Gemini Interactions 的协议 helper。型号规则来自 Bundle Manifest。
//

import Foundation

nonisolated enum GeminiModelContract {
    static func supportsInteractions(_ model: String) -> Bool {
        AIModelManifestRepository.shared.provider(.gemini)?.supportsWriting(model: model) == true
    }
}
