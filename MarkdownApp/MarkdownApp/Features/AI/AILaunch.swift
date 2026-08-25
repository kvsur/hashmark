//
//  AILaunch.swift
//  MarkdownApp
//
//  驱动 AI 会话 sheet(item:) 的载荷：过完配置门槛后携带 config + 选中的动作。
//  首页入口与编辑器内 AI 共用（DRY）。
//
//  选区润色时把「选中文本 + range」一并烘焙进这枚不可变载荷——让 sheet 与回填都从 launch 直接读取，
//  不再在 sheet 渲染时去读易受更新时序影响的 @State，避免「首次弹出偶尔读不到选中内容」这类竞态。
//

import Foundation

struct AILaunch: Identifiable {
    let id = UUID()
    let config: AIConfig
    let action: AIAction
    /// 选区润色携带：选中文本。整篇动作为 nil。
    var selectionText: String? = nil
    /// 选区润色携带：选中文本在源码中的 range，供接受后按 range 回填。整篇动作为 nil。
    var selectionRange: NSRange? = nil
}
