//
//  MarkdownEditingContext.swift
//  MarkdownApp
//
//  编辑规则的只读输入契约。范围统一采用 UTF-16 NSRange，与 UITextView.selectedRange 对齐，
//  避免 emoji、组合字符等内容在 Swift String.Index 与 UIKit offset 之间反复换算。
//

import Foundation

/// 一次编辑决策所需的最小快照；不持有 UITextView，因此纯逻辑规则可独立测试。
struct MarkdownEditingContext: Equatable {
    let text: String
    let selectedRange: NSRange
    /// 输入法正在组合的范围；nil 表示当前没有 marked text。
    let markedTextRange: NSRange?

    var utf16Length: Int { text.utf16.count }

    /// 有 marked text 时，自动续写/配对等规则应让系统输入法优先处理。
    var isComposingText: Bool { markedTextRange != nil }

    /// UIKit 理论上只提供合法范围，但外部全文替换、异步 AI 回填后仍需在规则边界防御。
    var hasValidRanges: Bool {
        contains(selectedRange) && markedTextRange.map(contains) != false
    }

    init(text: String, selectedRange: NSRange, markedTextRange: NSRange? = nil) {
        self.text = text
        self.selectedRange = selectedRange
        self.markedTextRange = markedTextRange
    }

    /// 判断 UTF-16 范围是否完整落在当前文本内；减法写法同时规避 location + length 溢出。
    func contains(_ range: NSRange) -> Bool {
        guard range.location != NSNotFound,
              range.location >= 0,
              range.length >= 0,
              range.location <= utf16Length else { return false }
        return range.length <= utf16Length - range.location
    }
}

/// UITextView 即将执行的原始替换。智能输入引擎可选择返回 mutation 接管它，或返回 nil 交还系统。
struct MarkdownProposedEdit: Equatable {
    let range: NSRange
    let replacementText: String

    init(range: NSRange, replacementText: String) {
        self.range = range
        self.replacementText = replacementText
    }

    func isValid(in context: MarkdownEditingContext) -> Bool {
        context.hasValidRanges && context.contains(range)
    }
}

