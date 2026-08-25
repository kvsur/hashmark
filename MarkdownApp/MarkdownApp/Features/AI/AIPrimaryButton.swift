//
//  AIPrimaryButton.swift
//  MarkdownApp
//
//  AI 流程统一主行动：保留品牌渐变，使用标准圆角与 52pt 触控高度；
//  禁用状态降低渐变强度但不完全去色，仍能维持 AI 功能的视觉识别。
//

import SwiftUI

struct AIPrimaryButton: View {
    let title: LocalizedStringKey
    var systemImage: String = "sparkles"
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .imageScale(.small)
                .foregroundStyle(Color.white.opacity(isEnabled ? 1 : 0.62))
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.aiGradient)
                        .opacity(isEnabled ? 1 : 0.42)
                )
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(AIPrimaryButtonStyle())
        .disabled(!isEnabled)
    }
}

private struct AIPrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
