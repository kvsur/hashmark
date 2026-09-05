//
//  DocumentNamingState.swift
//  MarkdownApp
//
//  文件名输入、实际磁盘名称与新文稿自动命名资格的纯状态模型。
//

import Foundation

nonisolated struct DocumentNamingState: Equatable, Sendable {
    enum RenameOrigin: Equatable, Sendable {
        case explicit
        case automatic
    }

    var input: String
    private(set) var actualName: String
    private(set) var isAutomaticTitleEligible: Bool

    init(route: DocumentRoute) {
        actualName = route.node.displayName
        input = route.isNewDocument ? "" : route.node.displayName
        isAutomaticTitleEligible = route.isNewDocument
    }

    var isInputBlank: Bool {
        input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    mutating func didRename(to url: URL, submittedName: String, origin: RenameOrigin) {
        actualName = url.deletingPathExtension().lastPathComponent
        let submittedWasBlank = submittedName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty

        switch origin {
        case .automatic:
            input = actualName
            isAutomaticTitleEligible = false
        case .explicit where submittedWasBlank:
            input = ""
        case .explicit:
            input = actualName
            isAutomaticTitleEligible = false
        }
    }

    mutating func didFailRename(origin: RenameOrigin) {
        if origin == .explicit {
            input = actualName
        }
    }

    mutating func synchronizeWithExternalURL(_ url: URL) {
        actualName = url.deletingPathExtension().lastPathComponent
        input = actualName
        isAutomaticTitleEligible = false
    }

    mutating func switchTo(_ node: DocumentNode) {
        actualName = node.displayName
        input = node.displayName
        isAutomaticTitleEligible = false
    }
}
