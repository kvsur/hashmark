//
//  AIAssistButton.swift
//  MarkdownApp
//
//  编辑态「AI 辅助编辑」入口（占位）：先放按钮 + 占位说明弹层，
//  后续再接入实际能力（续写/润色/整理）。抽成独立组件让 DocumentView 保持精简。
//

import SwiftUI

struct AIAssistButton: View {
    @State private var showPlaceholder = false

    var body: some View {
        Button {
            showPlaceholder = true
        } label: {
            Image(systemName: "sparkles")
        }
        .sheet(isPresented: $showPlaceholder) {
            AIAssistPlaceholderSheet()
        }
    }
}

/// 占位说明：功能未上线时给一个清晰、不崩的反馈。
private struct AIAssistPlaceholderSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("AI 辅助编辑", systemImage: "sparkles")
            } description: {
                Text("即将上线：用 AI 帮你续写、润色与整理 Markdown。")
            }
            .navigationTitle("AI 辅助编辑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
