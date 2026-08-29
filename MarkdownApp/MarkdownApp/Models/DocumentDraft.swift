//
//  DocumentDraft.swift
//  MarkdownApp
//
//  单篇文档在预览/编辑容器中的可持久化草稿状态。
//  文件访问以闭包注入，让 UI 只负责协调，也让加载、保存、切换顺序可独立回归。
//

import Foundation

nonisolated enum DocumentExternalChangeDecision: Equatable, Sendable {
    case ignore
    case markSaved
    case reload
    case preserveRemoteAndSaveDraft
}

struct DocumentDraft {
    private(set) var node: DocumentNode
    var text = ""
    private(set) var savedText = ""
    private(set) var isLoaded = false

    init(node: DocumentNode) {
        self.node = node
    }

    var isDirty: Bool {
        isLoaded && text != savedText
    }

    func decision(forRemoteText remoteText: String) -> DocumentExternalChangeDecision {
        guard isLoaded else { return .ignore }
        if remoteText == text { return isDirty ? .markSaved : .ignore }
        if remoteText == savedText { return .ignore }
        return isDirty ? .preserveRemoteAndSaveDraft : .reload
    }

    mutating func loadIfNeeded(readText: (URL) -> String) {
        guard !isLoaded else { return }
        text = readText(node.url)
        savedText = text
        isLoaded = true
    }

    mutating func loadIfNeeded(text: String) {
        guard !isLoaded else { return }
        self.text = text
        savedText = text
        isLoaded = true
    }

    mutating func markSaved(_ text: String, at url: URL) {
        guard node.url == url, self.text == text else { return }
        savedText = text
    }

    mutating func replaceDocument(with node: DocumentNode, text: String) {
        self.node = node
        self.text = text
        savedText = text
        isLoaded = true
    }

    mutating func reloadCleanText(_ text: String, at url: URL) {
        guard node.url == url, !isDirty else { return }
        self.text = text
        savedText = text
    }

    mutating func move(to url: URL) {
        guard node.url != url else { return }
        node = DocumentNode(
            url: url,
            kind: node.kind,
            modifiedAt: node.modifiedAt,
            fileSize: node.fileSize,
            childCount: node.childCount
        )
    }

    /// 保持既有保存语义：仅脏草稿触发写入，调用方决定如何呈现写入错误。
    mutating func save(writeText: (String, URL) -> Void) {
        guard isDirty else { return }
        writeText(text, node.url)
        savedText = text
    }

    /// 先保存旧 URL，再切换身份并读取新 URL；相同 URL 不做任何磁盘访问。
    @discardableResult
    mutating func switchTo(
        _ newNode: DocumentNode,
        readText: (URL) -> String,
        writeText: (String, URL) -> Void
    ) -> Bool {
        guard newNode.url != node.url else { return false }
        save(writeText: writeText)
        node = newNode
        text = readText(newNode.url)
        savedText = text
        isLoaded = true
        return true
    }
}
