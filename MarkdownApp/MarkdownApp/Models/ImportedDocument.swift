//
//  ImportedDocument.swift
//  MarkdownApp
//
//  外部打开/文件选择得到的只读预览载荷。
//

import Foundation

struct ImportedDocument: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let markdown: String

    init(url: URL, title: String, markdown: String) {
        self.url = url
        self.title = title
        self.markdown = markdown
    }

    static func load(
        from url: URL,
        readExternalText: (URL) -> String?
    ) -> ImportedDocument? {
        guard let text = readExternalText(url) else { return nil }
        return ImportedDocument(
            url: url,
            title: url.deletingPathExtension().lastPathComponent,
            markdown: text
        )
    }
}
