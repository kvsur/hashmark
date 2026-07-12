//
//  DocumentTreeNode.swift
//  MarkdownApp
//
//  目录/文档的「树」节点，用于一次性展开整棵结构（S10 快速切换器）。
//  与 DocumentNode 的区别：DocumentNode 是「一层」的平铺条目；这里带 children，
//  供 SwiftUI 的 OutlineGroup 直接渲染成可折叠树。
//

import Foundation

struct DocumentTreeNode: Identifiable {
    let node: DocumentNode
    /// 子节点：文件夹为其内容（可能为空数组），文件为 nil（OutlineGroup 据此判定叶子）。
    var children: [DocumentTreeNode]?

    var id: URL { node.url }
    var isFolder: Bool { node.isFolder }
}
