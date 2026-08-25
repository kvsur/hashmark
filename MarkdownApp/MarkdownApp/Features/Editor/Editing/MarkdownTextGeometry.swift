//
//  MarkdownTextGeometry.swift
//  MarkdownApp
//
//  UTF-16 文本范围工具。这里集中处理行边界，编辑规则不直接操作 String.Index。
//

import Foundation

enum MarkdownTextGeometry {
    static func contentLineRange(at location: Int, in text: String) -> NSRange {
        let ns = text as NSString
        let length = ns.length
        guard length > 0 else { return NSRange(location: 0, length: 0) }

        let safeLocation = min(max(location, 0), length)
        let lastUnit = ns.character(at: length - 1)
        if safeLocation == length, lastUnit == 0x0A || lastUnit == 0x0D {
            return NSRange(location: length, length: 0)
        }

        var start = 0, end = 0, contentsEnd = 0
        ns.getLineStart(
            &start,
            end: &end,
            contentsEnd: &contentsEnd,
            for: NSRange(location: min(safeLocation, length - 1), length: 0)
        )
        return NSRange(location: start, length: contentsEnd - start)
    }

    /// 覆盖选区触及的完整行；非空选区恰好止于下一行行首时，不把下一行算进去。
    static func selectedLinesRange(_ selection: NSRange, in text: String) -> NSRange {
        let ns = text as NSString
        guard ns.length > 0 else { return NSRange(location: 0, length: 0) }
        let startLine = contentLineRange(at: selection.location, in: text)
        let rawEnd = selection.location + selection.length
        let endProbe = selection.length > 0 ? max(selection.location, rawEnd - 1) : rawEnd
        let endLine = contentLineRange(at: endProbe, in: text)
        return NSRange(
            location: startLine.location,
            length: NSMaxRange(endLine) - startLine.location
        )
    }

    static func leadingWhitespace(in line: String) -> String {
        String(line.prefix { $0 == " " || $0 == "\t" })
    }

    static func removingOneIndentLevel(from prefix: String) -> String? {
        if prefix.hasPrefix("\t") { return String(prefix.dropFirst()) }
        let spaces = prefix.prefix { $0 == " " }.count
        guard spaces > 0 else { return nil }
        return String(prefix.dropFirst(min(4, spaces)))
    }
}
