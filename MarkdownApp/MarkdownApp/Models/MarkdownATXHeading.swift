//
//  MarkdownATXHeading.swift
//  MarkdownApp
//
//  大纲与文稿自动命名共享的单行 ATX 标题语义。
//

import Foundation

nonisolated struct MarkdownATXHeading: Equatable, Sendable {
    let level: Int
    let title: String
}

nonisolated enum MarkdownATXHeadingParser {
    static func parse(line: String) -> MarkdownATXHeading? {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        let level = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(level) else { return nil }

        let afterHashes = trimmed.dropFirst(level)
        guard afterHashes.first == " " || afterHashes.first == "\t" else { return nil }

        let title = afterHashes
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        return MarkdownATXHeading(level: level, title: title)
    }
}
