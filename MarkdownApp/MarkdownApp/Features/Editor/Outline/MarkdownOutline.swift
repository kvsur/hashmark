//
//  MarkdownOutline.swift
//  MarkdownApp
//
//  标题大纲纯逻辑：只识别 fenced code 之外的 ATX 标题，范围使用 UTF-16。
//

import Foundation

struct MarkdownOutlineItem: Identifiable, Equatable {
    let range: NSRange
    let level: Int
    let title: String
    /// 同级同名标题中的零基序号，供预览 DOM 在标题重复时精确定位。
    let occurrence: Int

    var id: Int { range.location }
}

enum MarkdownOutline {
    private struct HeadingIdentity: Hashable {
        let level: Int
        let title: String
    }

    static func items(in source: String) -> [MarkdownOutlineItem] {
        let ns = source as NSString
        var result: [MarkdownOutlineItem] = []
        var occurrences: [HeadingIdentity: Int] = [:]
        var fence: Character?
        ns.enumerateSubstrings(
            in: NSRange(location: 0, length: ns.length),
            options: [.byLines, .substringNotRequired]
        ) { _, range, _, _ in
            let line = ns.substring(with: range)
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let marker: Character = trimmed.first!
                if fence == nil { fence = marker }
                else if fence == marker { fence = nil }
                return
            }
            guard fence == nil else { return }
            guard let heading = MarkdownATXHeadingParser.parse(line: line) else { return }
            let identity = HeadingIdentity(level: heading.level, title: heading.title)
            let occurrence = occurrences[identity, default: 0]
            occurrences[identity] = occurrence + 1
            result.append(
                MarkdownOutlineItem(
                    range: range,
                    level: heading.level,
                    title: heading.title,
                    occurrence: occurrence
                )
            )
        }
        return result
    }
}
