//
//  BrowserSheet.swift
//  MarkdownApp
//
//  文件浏览器可弹出的编辑流程。
//

import Foundation

enum BrowserSheet: Identifiable {
    case newFolder
    case rename(DocumentNode)
    case move(DocumentNode)

    var id: String {
        switch self {
        case .newFolder: "newFolder"
        case .rename(let node): "rename-\(node.id.path)"
        case .move(let node): "move-\(node.id.path)"
        }
    }
}
