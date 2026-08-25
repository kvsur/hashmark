//
//  MarkdownLinePrefix.swift
//  MarkdownApp
//
//  只解析智能输入所需的行首容器与列表 marker，不承担完整 Markdown AST 职责。
//

import Foundation

struct MarkdownLinePrefix {
    enum Marker: Equatable {
        case unordered(Character)
        case ordered(number: Int, delimiter: Character)
    }

    let container: String
    let marker: Marker
    let spacing: String
    let isTask: Bool
    let content: String

    var isEmptyItem: Bool {
        content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var continuation: String {
        let markerText: String
        switch marker {
        case .unordered(let bullet): markerText = String(bullet)
        case .ordered(let number, let delimiter): markerText = "\(number + 1)\(delimiter)"
        }
        return container + markerText + spacing + (isTask ? "[ ] " : "")
    }

    static func parse(_ lineBeforeCaret: String) -> MarkdownLinePrefix? {
        let pattern = #"^([ \t]*(?:>[ \t]?)*)(?:(\d{1,9})([.)])|([-+*]))([ \t]+)(?:\[([ xX])\][ \t]+)?(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: lineBeforeCaret,
                range: NSRange(location: 0, length: (lineBeforeCaret as NSString).length)
              ) else { return nil }

        let ns = lineBeforeCaret as NSString
        func value(_ index: Int) -> String? {
            let range = match.range(at: index)
            return range.location == NSNotFound ? nil : ns.substring(with: range)
        }

        let marker: Marker
        if let digits = value(2), let number = Int(digits), let delimiter = value(3)?.first {
            marker = .ordered(number: number, delimiter: delimiter)
        } else if let bullet = value(4)?.first {
            marker = .unordered(bullet)
        } else {
            return nil
        }

        return MarkdownLinePrefix(
            container: value(1) ?? "",
            marker: marker,
            spacing: value(5) ?? " ",
            isTask: value(6) != nil,
            content: value(7) ?? ""
        )
    }

    /// 空嵌套项优先降低一级；顶层项则移除 marker，保留其 blockquote 容器。
    func emptyItemReplacement() -> String {
        let whitespace = MarkdownTextGeometry.leadingWhitespace(in: container)
        if let reduced = MarkdownTextGeometry.removingOneIndentLevel(from: whitespace) {
            let rest = String(container.dropFirst(whitespace.count))
            let markerText: String
            switch marker {
            case .unordered(let bullet): markerText = String(bullet)
            case .ordered(let number, let delimiter): markerText = "\(number)\(delimiter)"
            }
            return reduced + rest + markerText + spacing + (isTask ? "[ ] " : "")
        }
        return container
    }
}

