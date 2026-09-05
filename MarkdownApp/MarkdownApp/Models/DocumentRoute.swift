//
//  DocumentRoute.swift
//  MarkdownApp
//
//  文稿导航载荷：把文件身份与入口特有的初始编辑状态一起传递。
//

import Foundation

nonisolated enum DocumentInitialMode: String, Hashable, Sendable {
    case preview
    case edit
}

nonisolated struct DocumentRoute: Hashable, Sendable {
    let node: DocumentNode
    let initialMode: DocumentInitialMode
    let isNewDocument: Bool

    init(
        node: DocumentNode,
        initialMode: DocumentInitialMode = .preview,
        isNewDocument: Bool = false
    ) {
        self.node = node
        self.initialMode = initialMode
        self.isNewDocument = isNewDocument
    }
}
