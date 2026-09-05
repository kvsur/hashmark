//
//  MarkdownDocumentTitleInference.swift
//  MarkdownApp
//
//  从文稿第一物理行推导新建文稿的候选文件名。
//

import Foundation

nonisolated enum MarkdownDocumentTitleInference {
    static func title(from source: String) -> String? {
        let firstLine = String(source.prefix { !$0.isNewline })
        guard let heading = MarkdownATXHeadingParser.parse(line: firstLine),
              (1...3).contains(heading.level) else {
            return nil
        }
        return heading.title
    }
}
