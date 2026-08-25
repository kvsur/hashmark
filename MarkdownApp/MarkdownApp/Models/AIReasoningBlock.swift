//
//  AIReasoningBlock.swift
//  MarkdownApp
//
//  可展示推理摘要与 Provider 私有续传数据严格分离。UI 只读取 visibleText；
//  continuation 只能交还同一家 Provider Adapter，不能进入正文或跨 Provider 使用。
//

import Foundation

nonisolated struct AIReasoningBlock: Equatable {
    let visibleText: String
    let continuation: AIProviderContinuation?

    init(visibleText: String, continuation: AIProviderContinuation? = nil) {
        self.visibleText = visibleText
        self.continuation = continuation
    }
}

