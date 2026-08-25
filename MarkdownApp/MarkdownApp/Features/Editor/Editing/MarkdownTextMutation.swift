//
//  MarkdownTextMutation.swift
//  MarkdownApp
//
//  编辑规则的唯一输出：一次连续替换及替换完成后的选区。UIKit 层只负责原子应用它，
//  从而让自动续列表、格式切换等行为各自保持为一次可撤销事务。
//

import Foundation

struct MarkdownTextMutation: Equatable {
    enum Kind: Equatable {
        /// 接管用户正在输入的字符，例如 Return 后自动补下一条列表 marker。
        case smartInput
        /// 用户显式触发的格式/结构命令，例如加粗或缩进。
        case command
    }

    /// 在 mutation 产生时那份 raw Markdown 中要替换的 UTF-16 范围。
    let range: NSRange
    let replacementText: String
    /// 替换后的 UTF-16 选区；光标用 length == 0 表示。
    let selectedRangeAfter: NSRange
    let kind: Kind

    init(
        range: NSRange,
        replacementText: String,
        selectedRangeAfter: NSRange,
        kind: Kind
    ) {
        self.range = range
        self.replacementText = replacementText
        self.selectedRangeAfter = selectedRangeAfter
        self.kind = kind
    }

    /// 同时校验替换前 range 与替换后 selection，防止 stale mutation 覆盖错误内容。
    func isValid(in context: MarkdownEditingContext) -> Bool {
        guard context.hasValidRanges, context.contains(range) else { return false }
        let resultLength = context.utf16Length - range.length + replacementText.utf16.count
        guard selectedRangeAfter.location != NSNotFound,
              selectedRangeAfter.location >= 0,
              selectedRangeAfter.length >= 0,
              selectedRangeAfter.location <= resultLength else { return false }
        return selectedRangeAfter.length <= resultLength - selectedRangeAfter.location
    }
}

