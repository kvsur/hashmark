//
//  AILaunch.swift
//  MarkdownApp
//
//  驱动 AI 会话 sheet(item:) 的载荷：过完配置门槛后携带 config + 选中的动作。
//  首页入口与编辑器内 AI 共用（DRY）。
//

import Foundation

struct AILaunch: Identifiable {
    let id = UUID()
    let config: AIConfig
    let action: AIAction
}
