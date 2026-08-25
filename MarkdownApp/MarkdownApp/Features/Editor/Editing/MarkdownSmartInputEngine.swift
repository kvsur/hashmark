//
//  MarkdownSmartInputEngine.swift
//  MarkdownApp
//
//  接管少量明确的输入：智能 Return、URL 粘贴与保守配对。无法确定时返回 nil，交给 UIKit。
//

import Foundation

enum MarkdownSmartInputEngine {
    static func mutation(
        for edit: MarkdownProposedEdit,
        in context: MarkdownEditingContext
    ) -> MarkdownTextMutation? {
        guard edit.isValid(in: context), !context.isComposingText else { return nil }

        if edit.replacementText == "\n" {
            return newlineMutation(for: edit, in: context)
        }
        if let urlMutation = linkPasteMutation(for: edit, in: context) {
            return urlMutation
        }
        return pairedCharacterMutation(for: edit, in: context)
    }

    private static func newlineMutation(
        for edit: MarkdownProposedEdit,
        in context: MarkdownEditingContext
    ) -> MarkdownTextMutation? {
        guard edit.range.length == 0 else { return nil }
        let lineRange = MarkdownTextGeometry.contentLineRange(at: edit.range.location, in: context.text)
        let ns = context.text as NSString
        let prefixLength = max(0, edit.range.location - lineRange.location)
        let beforeCaret = ns.substring(with: NSRange(location: lineRange.location, length: prefixLength))

        if let list = MarkdownLinePrefix.parse(beforeCaret) {
            if list.isEmptyItem {
                let replacement = list.emptyItemReplacement()
                return MarkdownTextMutation(
                    range: NSRange(location: lineRange.location, length: prefixLength),
                    replacementText: replacement,
                    selectedRangeAfter: NSRange(
                        location: lineRange.location + replacement.utf16.count,
                        length: 0
                    ),
                    kind: .smartInput
                )
            }
            let replacement = "\n" + list.continuation
            return insertionMutation(edit: edit, replacement: replacement)
        }

        if let quote = quotePrefix(in: beforeCaret) {
            let content = String(beforeCaret.dropFirst(quote.count))
            if content.trimmingCharacters(in: .whitespaces).isEmpty {
                let reduced = removingLastQuote(from: quote)
                return MarkdownTextMutation(
                    range: NSRange(location: lineRange.location, length: prefixLength),
                    replacementText: reduced,
                    selectedRangeAfter: NSRange(location: lineRange.location + reduced.utf16.count, length: 0),
                    kind: .smartInput
                )
            }
            return insertionMutation(edit: edit, replacement: "\n" + quote)
        }

        if isInsideFence(before: lineRange.location, in: context.text) {
            let indent = MarkdownTextGeometry.leadingWhitespace(in: beforeCaret)
            guard !indent.isEmpty else { return nil }
            return insertionMutation(edit: edit, replacement: "\n" + indent)
        }
        return nil
    }

    private static func insertionMutation(
        edit: MarkdownProposedEdit,
        replacement: String
    ) -> MarkdownTextMutation {
        MarkdownTextMutation(
            range: edit.range,
            replacementText: replacement,
            selectedRangeAfter: NSRange(location: edit.range.location + replacement.utf16.count, length: 0),
            kind: .smartInput
        )
    }

    private static func linkPasteMutation(
        for edit: MarkdownProposedEdit,
        in context: MarkdownEditingContext
    ) -> MarkdownTextMutation? {
        guard edit.range.length > 0,
              edit.replacementText.utf16.count > 4,
              let url = URL(string: edit.replacementText),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        let selected = (context.text as NSString).substring(with: edit.range)
        guard !selected.contains("\n") else { return nil }
        let replacement = "[\(selected)](\(edit.replacementText))"
        return MarkdownTextMutation(
            range: edit.range,
            replacementText: replacement,
            selectedRangeAfter: NSRange(location: edit.range.location + replacement.utf16.count, length: 0),
            kind: .smartInput
        )
    }

    private static func pairedCharacterMutation(
        for edit: MarkdownProposedEdit,
        in context: MarkdownEditingContext
    ) -> MarkdownTextMutation? {
        let pairs: [String: String] = ["[": "]", "(": ")", "`": "`"]
        if let closing = pairs[edit.replacementText] {
            let selected = (context.text as NSString).substring(with: edit.range)
            let replacement = edit.replacementText + selected + closing
            return MarkdownTextMutation(
                range: edit.range,
                replacementText: replacement,
                selectedRangeAfter: NSRange(
                    location: edit.range.location + edit.replacementText.utf16.count,
                    length: edit.range.length
                ),
                kind: .smartInput
            )
        }

        guard edit.range.length == 0, ["]", ")", "`"].contains(edit.replacementText) else { return nil }
        let ns = context.text as NSString
        guard edit.range.location < ns.length,
              ns.substring(with: NSRange(location: edit.range.location, length: 1)) == edit.replacementText else {
            return nil
        }
        return MarkdownTextMutation(
            range: edit.range,
            replacementText: "",
            selectedRangeAfter: NSRange(location: edit.range.location + 1, length: 0),
            kind: .smartInput
        )
    }

    private static func quotePrefix(in line: String) -> String? {
        let pattern = #"^[ \t]*(?:>[ \t]?)+"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: line,
                range: NSRange(location: 0, length: (line as NSString).length)
              ) else { return nil }
        return (line as NSString).substring(with: match.range)
    }

    private static func removingLastQuote(from prefix: String) -> String {
        let ns = prefix as NSString
        let range = ns.range(of: ">", options: .backwards)
        guard range.location != NSNotFound else { return prefix }
        var end = NSMaxRange(range)
        if end < ns.length, [" ", "\t"].contains(ns.substring(with: NSRange(location: end, length: 1))) {
            end += 1
        }
        return ns.replacingCharacters(in: NSRange(location: range.location, length: end - range.location), with: "")
    }

    private static func isInsideFence(before location: Int, in text: String) -> Bool {
        let prefix = (text as NSString).substring(to: max(0, min(location, (text as NSString).length)))
        var active: Character?
        prefix.enumerateLines { line, _ in
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            let marker: Character? = trimmed.hasPrefix("```") ? "`" : (trimmed.hasPrefix("~~~") ? "~" : nil)
            guard let marker else { return }
            if active == nil { active = marker }
            else if active == marker { active = nil }
        }
        return active != nil
    }
}

