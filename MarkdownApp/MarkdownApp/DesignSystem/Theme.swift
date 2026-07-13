//
//  Theme.swift
//  MarkdownApp
//
//  全 App 统一的设计常量（design tokens）：字体、圆角、间距。
//  类比前端：这相当于一份 tokens 文件，集中管理避免魔法数字散落各处。
//
//  颜色说明：深浅色适配直接用系统语义颜色（.primary / Color(.systemBackground) 等），
//  它们会随系统深浅色自动切换，无需我们手写两套。所以这里暂不定义颜色常量。
//

import SwiftUI

enum Theme {
    // MARK: - 字体

    /// 等宽字体（编辑器、代码、文件名用）。
    static func mono(_ size: CGFloat = 16, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: - 形状

    /// 卡片/玻璃面板统一圆角。
    static let cornerRadius: CGFloat = 16

    // MARK: - 间距

    static let spacing: CGFloat = 12

    // MARK: - 颜色

    /// AI 功能统一品牌渐变：用于所有 AI 入口按钮的图标/文字着色，保证全 App 一致（DRY）。
    /// 这是有意的品牌色（区别于随深浅色自适应的语义色），故作为设计常量集中在此。
    static let aiGradient = LinearGradient(
        colors: [
            Color(red: 0.55, green: 0.36, blue: 0.96),  // 紫
            Color(red: 0.36, green: 0.60, blue: 0.98),  // 蓝
            Color(red: 0.93, green: 0.42, blue: 0.72)   // 粉
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
