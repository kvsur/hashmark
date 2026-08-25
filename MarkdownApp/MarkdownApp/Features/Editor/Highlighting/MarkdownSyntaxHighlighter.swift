//
//  MarkdownSyntaxHighlighter.swift
//  MarkdownApp
//
//  raw Markdown 的非破坏性视觉层：只写 textStorage 属性，不改变字符或保存内容。
//

import UIKit

enum MarkdownSyntaxHighlighter {
    static func apply(to textView: UITextView) {
        guard textView.markedTextRange == nil else { return }
        let storage = textView.textStorage
        let fullRange = NSRange(location: 0, length: storage.length)
        let selection = textView.selectedRange
        let baseFont = UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
        let base: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: UIColor.label
        ]

        storage.beginEditing()
        storage.setAttributes(base, range: fullRange)
        apply(#"(?m)^#{1,6}\s+.*$"#, color: .label,
              font: .monospacedSystemFont(ofSize: 17, weight: .semibold), to: storage)
        apply(#"(?m)^(#{1,6})(?=\s)"#, color: .tertiaryLabel, font: baseFont, to: storage)
        apply(#"(?m)^[ \t]*(?:>\s?|[-+*]\s+|\d{1,9}[.)]\s+|[-+*]\s+\[[ xX]\]\s+)"#,
              color: .systemIndigo, font: baseFont, to: storage)
        apply(#"`{1,3}|~{2}|\*{1,2}|_{1,2}"#, color: .secondaryLabel, font: baseFont, to: storage)
        apply(#"(?<=\]\()[^)]+(?=\))"#, color: .systemBlue, font: baseFont, to: storage)
        apply(#"(?m)^\s*(?:```|~~~).*$"#, color: .systemOrange, font: baseFont, to: storage)
        applyParagraphStyles(to: storage)
        storage.endEditing()

        if selection.location != NSNotFound, NSMaxRange(selection) <= storage.length {
            textView.selectedRange = selection
        }
        textView.typingAttributes = base
    }

    private static func apply(
        _ pattern: String,
        color: UIColor,
        font: UIFont,
        to storage: NSTextStorage
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let full = NSRange(location: 0, length: storage.length)
        for match in regex.matches(in: storage.string, range: full) where match.range.length > 0 {
            storage.addAttributes([.foregroundColor: color, .font: font], range: match.range)
        }
    }

    /// 视觉悬挂缩进：长列表行换行后对齐正文；属性不进入 raw Markdown。
    private static func applyParagraphStyles(to storage: NSTextStorage) {
        let ns = storage.string as NSString
        let regex = try? NSRegularExpression(
            pattern: #"(?m)^([ \t]*(?:>\s?)*)(?:[-+*]\s+(?:\[[ xX]\]\s+)?|\d{1,9}[.)]\s+)"#
        )
        let full = NSRange(location: 0, length: ns.length)
        regex?.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let match else { return }
            let paragraph = ns.paragraphRange(for: match.range)
            let style = NSMutableParagraphStyle()
            style.firstLineHeadIndent = 0
            style.headIndent = CGFloat(match.range.length) * 9.6
            storage.addAttribute(.paragraphStyle, value: style, range: paragraph)
        }
    }
}
