//
//  AIConfigGate.swift
//  MarkdownApp
//
//  AI 入口的共享门槛：任一 AIConfig 字段（BaseURL/Model/API Key）为空就不得进入 AI，
//  先弹提示、再一键跳转到 AI 配置页。所有 AI 入口（首页/编辑器）统一挂此修饰符，
//  把「校验 + 未配置提示 + 跳配置」收敛一处（DRY）。
//

import SwiftUI

private struct AIConfigGateModifier: ViewModifier {
    /// 外部想进入 AI 时把它置 true；门槛消费后自动复位。
    @Binding var trigger: Bool
    let store: AIConfigStore
    /// 配置完整时回调，外部据此呈现 AI 会话（AIWritingView）。
    let onReady: (AIConfig) -> Void

    @State private var showNotConfigured = false
    @State private var showEditor = false

    func body(content: Content) -> some View {
        content
            .onChange(of: trigger) { _, wants in
                guard wants else { return }
                trigger = false
                let config = store.load()
                if config.isComplete {
                    onReady(config)
                } else {
                    showNotConfigured = true
                }
            }
            .alert("AI Not Configured", isPresented: $showNotConfigured) {
                Button("Configure") { showEditor = true }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Fill in the base URL, model, and API key to use AI writing.")
            }
            .sheet(isPresented: $showEditor) {
                AIConfigEditorView(store: store)
            }
    }
}

extension View {
    /// AI 入口门槛：`trigger` 置 true 时校验配置——完整则 onReady(config)，否则提示并可跳配置页。
    func aiConfigGate(
        trigger: Binding<Bool>,
        store: AIConfigStore,
        onReady: @escaping (AIConfig) -> Void
    ) -> some View {
        modifier(AIConfigGateModifier(trigger: trigger, store: store, onReady: onReady))
    }
}
