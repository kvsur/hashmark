//
//  DocumentNode.swift
//  MarkdownApp
//
//  文件树中的一个节点：文件夹或 Markdown 文件。
//  节点直接映射磁盘上的真实条目，`url` 即其在文件系统中的位置。
//

import Foundation

struct DocumentNode: Identifiable, Hashable {
    enum Kind {
        case folder
        case markdown
    }

    let url: URL
    let kind: Kind
    let modifiedAt: Date

    /// 用 URL 作为稳定唯一标识。
    var id: URL { url }

    /// 磁盘上的完整名称（文件夹名，或含 .md 的文件名）。
    var name: String { url.lastPathComponent }

    var isFolder: Bool { kind == .folder }

    /// 列表展示用标题：Markdown 去掉扩展名，文件夹用原名。
    var displayName: String {
        isFolder ? name : url.deletingPathExtension().lastPathComponent
    }

    /// 列表图标。
    var systemImage: String {
        isFolder ? "folder.fill" : "doc.text"
    }
}
