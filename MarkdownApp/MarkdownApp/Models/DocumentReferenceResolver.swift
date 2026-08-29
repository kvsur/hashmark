//
//  DocumentReferenceResolver.swift
//  MarkdownApp
//
//  把文档树中的 URL 选择解析成 AI 文档引用附件。
//

import Foundation

struct DocumentReferenceResolver {
    static func attachments(
        in roots: [DocumentTreeNode],
        selectedURLs: Set<URL>,
        readText: (URL) -> String
    ) -> [AIAttachment] {
        fileNodes(in: roots)
            .filter { selectedURLs.contains($0.url) }
            .compactMap { node in
                let text = readText(node.url)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return .documentReference(
                    url: node.url,
                    name: node.displayName,
                    text: text
                )
            }
    }

    static func attachments(
        in roots: [DocumentTreeNode],
        selectedURLs: Set<URL>,
        readText: (URL) async throws -> String
    ) async -> [AIAttachment] {
        var attachments: [AIAttachment] = []
        for node in fileNodes(in: roots) where selectedURLs.contains(node.url) {
            guard let value = try? await readText(node.url) else { continue }
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            attachments.append(
                .documentReference(url: node.url, name: node.displayName, text: text)
            )
        }
        return attachments
    }

    private static func fileNodes(in nodes: [DocumentTreeNode]) -> [DocumentNode] {
        nodes.flatMap { node -> [DocumentNode] in
            if let children = node.children {
                return fileNodes(in: children)
            }
            return [node.node]
        }
    }
}
