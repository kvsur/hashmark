//
//  AIActionPopover.swift
//  MarkdownApp
//
//  AI 辅助的动作选择列表（弹层内容）：把 AIAction 的四个预设排成一列可点的行。
//  抽成独立视图便于复用，并让调用方用 .popover 锚定到具体按钮——避免 confirmationDialog
//  在 iOS 26 下没有锚点、飘到屏幕顶部的问题（应贴着触发它的 AI 按钮出现）。
//

import SwiftUI

struct AIActionPopover: View {
    /// 选中某个动作时回调；关闭弹层与后续流程由调用方处理。
    let onSelect: (AIAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("AI Assist")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.spacing)
                .padding(.top, Theme.spacing)
                .padding(.bottom, 6)

            ForEach(Array(AIAction.allCases.enumerated()), id: \.element.id) { index, action in
                if index > 0 { Divider().padding(.leading, Theme.spacing) }
                Button {
                    onSelect(action)
                } label: {
                    Label(action.label, systemImage: action.systemImage)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.spacing)
                        .padding(.vertical, 12)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        // 给弹层一个合适的宽度，避免过窄挤压文字或过宽显得空。
        .frame(width: 220)
    }
}
