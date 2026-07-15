//
//  HomeAIButton.swift
//  MarkdownApp
//
//  首页大号 AI 写作入口：品牌渐变、加大加厚的悬浮胶囊，比工具栏图标显著得多，
//  但不做「长长扁扁」的通栏按钮——用带阴影的胶囊，醒目又克制。挂在根目录浏览器底部。
//

import SwiftUI

struct HomeAIButton: View {
    let action: () -> Void

    var body: some View {
        // 点击先给一下触觉反馈，再执行真正动作（与工具栏 AI 入口统一手感）。
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
