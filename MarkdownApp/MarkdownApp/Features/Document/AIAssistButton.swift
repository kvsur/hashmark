//
//  AIAssistButton.swift
//  MarkdownApp
//
//  彩色 AI 入口按钮（纯展示）：sparkles + 品牌渐变着色，点击执行传入的 action。
//  可复用——编辑器/预览工具栏用仅图标；首页可传 title 显示「AI 写作」（做大）。
//  真正的 AI 流程由调用方组织（上下文、门槛、会话），本按钮不关心。
//

import SwiftUI

struct AIAssistButton: View {
    /// 可选文字标签：nil = 仅图标；非 nil = 图标+文字。
    var title: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
                // AI 品牌渐变着色，让入口一眼可辨（图标与文字统一上色）。
                .foregroundStyle(Theme.aiGradient)
        }
    }

    @ViewBuilder
    private var label: some View {
        if let title {
            // 用显式 HStack 而非 Label：工具栏会把 Label 折叠成 icon-only 而丢掉文字，
            // 显式拼接可保证图标与文字都出现（两者一起被上面的渐变着色）。
            // 文字在前、图标在后（"AI" + sparkles）。
            HStack(spacing: 5) {
                Text(title)
                Image(systemName: "sparkles")
            }
        } else {
            Image(systemName: "sparkles")
        }
    }
}
