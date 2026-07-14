//
//  Haptics.swift
//  MarkdownApp
//
//  触觉反馈的统一入口：把 UIKit 的 FeedbackGenerator 收敛到一处，业务侧只按语义调用
//  （轻点 / 柔和 / 完成），不各自 new 一个 generator，也不散落 import UIKit。
//  语言/控件会变，但「同一种交互给同一种手感」的约定不变——集中在这里便于统一调校。
//

import UIKit

enum Haptics {
    /// 轻点：用于按钮点击等主动、明确的交互（如 AI 写作入口）。
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// 柔和：更细微的一下，用于「状态悄然切换」（如预览↔编辑切换、开始生成）。
    static func soft() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    /// 完成：成功型通知反馈，用于「一段流程结束」（如 AI 生成完成）。
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
