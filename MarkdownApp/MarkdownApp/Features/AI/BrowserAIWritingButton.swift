//
//  BrowserAIWritingButton.swift
//  MarkdownApp
//
//  文件浏览器各层级共用的 AI 写作入口：保留品牌渐变、触觉反馈与悬浮胶囊样式。
//

import SwiftUI

struct BrowserAIWritingButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: { Haptics.light(); action() }) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title3)
                Text("AI Writing")
                    .font(.headline)
            }
            .foregroundStyle(.white)
            .padding(.vertical, 16)
            .padding(.horizontal, 30)
            .background(Theme.aiGradient, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
    }
}
