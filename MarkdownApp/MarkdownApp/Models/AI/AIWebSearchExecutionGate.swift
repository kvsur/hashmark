//
//  AIWebSearchExecutionGate.swift
//  MarkdownApp
//
//  五家 Adapter 共用的领域层搜索证据门。它不理解任何 Provider wire，
//  只保证搜索必选时，正文不能先于搜索证据出现，且流结束前必须有证据。
//

import Foundation

nonisolated struct AIWebSearchExecutionGate {
    let isRequired: Bool
    private(set) var hasEvidence = false

    mutating func accepts(_ event: AIStreamEvent) -> Bool {
        hasEvidence = hasEvidence || event.isWebSearchExecutionEvidence
        return !isRequired || hasEvidence || !event.isAnswerText
    }

    var isSatisfied: Bool { !isRequired || hasEvidence }
}
