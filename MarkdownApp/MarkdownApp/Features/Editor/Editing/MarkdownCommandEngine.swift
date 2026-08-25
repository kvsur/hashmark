//
//  MarkdownCommandEngine.swift
//  MarkdownApp
//
//  显式 Markdown 命令的纯逻辑实现。UI 入口只发命令，不复制字符串变换。
//

import Foundation

enum MarkdownCommandEngine {
    static func mutation(
        for command: MarkdownEditorCommand,
        in context: MarkdownEditingContext
    ) -> MarkdownTextMutation? {
        guard context.hasValidRanges, !context.isComposingText else { return nil }
        switch command {
        case .toggleInline(let style): return toggleInline(style, in: context)
        case .toggleBlock(let style): return toggleBlock(style, in: context)
        case .indent: return transformLines(in: context, mode: .indent)
        case .outdent: return transformLines(in: context, mode: .outdent)
        case .moveLines(let direction): return moveLines(direction, in: context)
        }
    }

    private static func toggleInline(
        _ style: MarkdownInlineStyle,
        in context: MarkdownEditingContext
    ) -> MarkdownTextMutation? {
        if style == .link { return toggleLink(in: context) }
        let delimiter: String
        switch style {
        case .bold: delimiter = "**"
        case .italic: delimiter = "_"
        case .strikethrough: delimiter = "~~"
        case .inlineCode: delimiter = "`"
        case .link: return nil
        }

        let ns = context.text as NSString
        let selection = context.selectedRange
        let selected = ns.substring(with: selection)
        let d = (delimiter as NSString).length

        if selection.length >= d * 2,
           selected.hasPrefix(delimiter), selected.hasSuffix(delimiter) {
            let inner = (selected as NSString).substring(with: NSRange(location: d, length: selection.length - d * 2))
            return mutation(selection, inner, NSRange(location: selection.location, length: (inner as NSString).length))
        }

        if selection.location >= d, NSMaxRange(selection) + d <= ns.length {
            let before = ns.substring(with: NSRange(location: selection.location - d, length: d))
            let after = ns.substring(with: NSRange(location: NSMaxRange(selection), length: d))
            if before == delimiter, after == delimiter {
                let range = NSRange(location: selection.location - d, length: selection.length + d * 2)
                return mutation(range, selected, NSRange(location: range.location, length: selection.length))
            }
        }

        let replacement = delimiter + selected + delimiter
        let after = selection.length == 0
            ? NSRange(location: selection.location + d, length: 0)
            : NSRange(location: selection.location + d, length: selection.length)
        return mutation(selection, replacement, after)
    }

    private static func toggleLink(in context: MarkdownEditingContext) -> MarkdownTextMutation {
        let selection = context.selectedRange
        let selected = (context.text as NSString).substring(with: selection)
        let replacement = "[\(selected)]()"
        let urlLocation = selection.location + selected.utf16.count + 3
        return mutation(selection, replacement, NSRange(location: urlLocation, length: 0))
    }

    private enum LineMode { case indent, outdent }

    private static func transformLines(
        in context: MarkdownEditingContext,
        mode: LineMode
    ) -> MarkdownTextMutation? {
        let range = MarkdownTextGeometry.selectedLinesRange(context.selectedRange, in: context.text)
        let original = (context.text as NSString).substring(with: range)
        // 光标位于完全空白的新行时，缩进应先建立一级可继续输入的缩进；
        // outdent 在没有任何缩进时仍保持 no-op。多行选区中的空行继续跳过，避免批量制造尾随空格。
        if context.selectedRange.length == 0, original.isEmpty {
            guard mode == .indent else { return nil }
            let indent = "    "
            return mutation(
                range,
                indent,
                NSRange(location: range.location + indent.utf16.count, length: 0)
            )
        }
        let transformed = original
            .components(separatedBy: "\n")
            .map { line -> String in
                guard !line.isEmpty else { return line }
                switch mode {
                case .indent: return "    " + line
                case .outdent:
                    if line.hasPrefix("\t") { return String(line.dropFirst()) }
                    return String(line.dropFirst(min(4, line.prefix { $0 == " " }.count)))
                }
            }
            .joined(separator: "\n")
        guard transformed != original else { return nil }
        let selectedAfter = context.selectedRange.length == 0
            ? NSRange(
                location: max(range.location, context.selectedRange.location + transformed.utf16.count - original.utf16.count),
                length: 0
              )
            : NSRange(location: range.location, length: transformed.utf16.count)
        return mutation(range, transformed, selectedAfter)
    }

    private static func toggleBlock(
        _ style: MarkdownBlockStyle,
        in context: MarkdownEditingContext
    ) -> MarkdownTextMutation? {
        let range = MarkdownTextGeometry.selectedLinesRange(context.selectedRange, in: context.text)
        let original = (context.text as NSString).substring(with: range)
        if style == .fencedCode {
            let trimmed = original.trimmingCharacters(in: .newlines)
            let replacement: String
            if trimmed.hasPrefix("```"), trimmed.hasSuffix("```"), trimmed.count >= 6 {
                replacement = String(trimmed.dropFirst(3).dropLast(3)).trimmingCharacters(in: .newlines)
            } else {
                replacement = "```\n\(original)\n```"
            }
            return mutation(range, replacement, NSRange(location: range.location, length: replacement.utf16.count))
        }

        // 空文档或段落后的空行也必须能建立块结构。光标放到前缀末尾，用户可直接输入；
        // 再次执行同一命令时会走下方 matches/removingPrefix，恢复为空行。
        if context.selectedRange.length == 0, original.isEmpty {
            let replacement = addingPrefix(for: style, to: "", orderedIndex: 1)
            return mutation(
                range,
                replacement,
                NSRange(location: range.location + replacement.utf16.count, length: 0)
            )
        }

        let lines = original.components(separatedBy: "\n")
        let nonempty = lines.filter { !$0.isEmpty }
        guard !nonempty.isEmpty else { return nil }
        let removing = nonempty.allSatisfy { matches(style, line: $0) }
        var orderedIndex = 1
        let transformed = lines.map { line -> String in
            guard !line.isEmpty else { return line }
            if removing { return removingPrefix(for: style, from: line) }
            let stripped = strippingKnownBlockPrefix(from: line)
            defer { if case .orderedList = style { orderedIndex += 1 } }
            return addingPrefix(for: style, to: stripped, orderedIndex: orderedIndex)
        }.joined(separator: "\n")
        guard transformed != original else { return nil }
        let selectionAfter = context.selectedRange.length == 0
            ? NSRange(
                location: min(
                    range.location + transformed.utf16.count,
                    max(range.location, context.selectedRange.location + transformed.utf16.count - original.utf16.count)
                ),
                length: 0
              )
            : NSRange(location: range.location, length: transformed.utf16.count)
        return mutation(range, transformed, selectionAfter)
    }

    private static func moveLines(
        _ direction: MarkdownLineMoveDirection,
        in context: MarkdownEditingContext
    ) -> MarkdownTextMutation? {
        let ns = context.text as NSString
        guard ns.length > 0 else { return nil }
        let selection = context.selectedRange
        let endProbe = selection.length > 0 ? NSMaxRange(selection) - 1 : selection.location
        let startParagraph = ns.paragraphRange(for: NSRange(location: min(selection.location, ns.length - 1), length: 0))
        let endParagraph = ns.paragraphRange(for: NSRange(location: min(max(endProbe, 0), ns.length - 1), length: 0))
        let block = NSRange(location: startParagraph.location, length: NSMaxRange(endParagraph) - startParagraph.location)
        let blockText = ns.substring(with: block)

        switch direction {
        case .up:
            guard block.location > 0 else { return nil }
            let previous = ns.paragraphRange(for: NSRange(location: block.location - 1, length: 0))
            let previousText = ns.substring(with: previous)
            let combined = NSRange(location: previous.location, length: NSMaxRange(block) - previous.location)
            return mutation(
                combined,
                blockText + previousText,
                NSRange(location: previous.location, length: block.length)
            )
        case .down:
            guard NSMaxRange(block) < ns.length else { return nil }
            let next = ns.paragraphRange(for: NSRange(location: NSMaxRange(block), length: 0))
            let nextText = ns.substring(with: next)
            let combined = NSRange(location: block.location, length: NSMaxRange(next) - block.location)
            return mutation(
                combined,
                nextText + blockText,
                NSRange(location: block.location + next.length, length: block.length)
            )
        }
    }

    private static func matches(_ style: MarkdownBlockStyle, line: String) -> Bool {
        // 只忽略行首缩进，保留 marker 后面的空格；`- `、`1. `、`> ` 这类尚未输入正文的
        // 空项正依赖这个空格识别自身，若把两端空白都 trim 掉就无法再次 toggle 移除。
        let indent = MarkdownTextGeometry.leadingWhitespace(in: line)
        let value = String(line.dropFirst(indent.count))
        switch style {
        case .heading(let level): return value.hasPrefix(String(repeating: "#", count: level.rawValue) + " ")
        case .blockquote: return value.hasPrefix("> ")
        case .unorderedList: return value.range(of: #"^[-+*]\s+"#, options: .regularExpression) != nil
        case .orderedList: return value.range(of: #"^\d{1,9}[.)]\s+"#, options: .regularExpression) != nil
        case .taskList: return value.range(of: #"^[-+*]\s+\[[ xX]\]\s+"#, options: .regularExpression) != nil
        case .fencedCode: return false
        }
    }

    private static func addingPrefix(
        for style: MarkdownBlockStyle,
        to line: String,
        orderedIndex: Int
    ) -> String {
        let indent = MarkdownTextGeometry.leadingWhitespace(in: line)
        let content = String(line.dropFirst(indent.count))
        let prefix: String
        switch style {
        case .heading(let level): prefix = String(repeating: "#", count: level.rawValue) + " "
        case .blockquote: prefix = "> "
        case .unorderedList: prefix = "- "
        case .orderedList: prefix = "\(orderedIndex). "
        case .taskList: prefix = "- [ ] "
        case .fencedCode: prefix = ""
        }
        return indent + prefix + content
    }

    private static func removingPrefix(for style: MarkdownBlockStyle, from line: String) -> String {
        let indent = MarkdownTextGeometry.leadingWhitespace(in: line)
        let content = String(line.dropFirst(indent.count))
        let pattern: String
        switch style {
        case .heading: pattern = #"^#{1,6}\s+"#
        case .blockquote: pattern = #"^>\s?"#
        case .unorderedList: pattern = #"^[-+*]\s+"#
        case .orderedList: pattern = #"^\d{1,9}[.)]\s+"#
        case .taskList: pattern = #"^[-+*]\s+\[[ xX]\]\s+"#
        case .fencedCode: return line
        }
        return indent + content.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }

    private static func strippingKnownBlockPrefix(from line: String) -> String {
        let indent = MarkdownTextGeometry.leadingWhitespace(in: line)
        let content = String(line.dropFirst(indent.count))
        let pattern = #"^(?:#{1,6}\s+|>\s?|[-+*]\s+(?:\[[ xX]\]\s+)?|\d{1,9}[.)]\s+)"#
        return indent + content.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }

    private static func mutation(
        _ range: NSRange,
        _ replacement: String,
        _ selection: NSRange
    ) -> MarkdownTextMutation {
        MarkdownTextMutation(
            range: range,
            replacementText: replacement,
            selectedRangeAfter: selection,
            kind: .command
        )
    }
}
