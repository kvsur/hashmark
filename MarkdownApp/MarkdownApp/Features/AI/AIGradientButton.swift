//
//  AIGradientButton.swift
//  MarkdownApp
//
//  AI 场景统一的主行动按钮：品牌渐变胶囊、居中不铺满整行（避免「长长扁扁的按钮」），
//  禁用时去色+降透明清晰可辨。开始生成 / 确定 / 提交 等主行动复用它（DRY）。
//

import SwiftUI

struct AIGradientButton: View {
    let title: LocalizedStringKey
    var systemImage: String = "sparkles"
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.vertical, 14)
                .padding(.horizontal, 32)
                .background(Theme.aiGradient, in: Capsule())
        }
        .buttonStyle(.plain)
        .grayscale(isEnabled ? 0 : 1)
        .opacity(isEnabled ? 1 : 0.5)
        .disabled(!isEnabled)
    }
}
