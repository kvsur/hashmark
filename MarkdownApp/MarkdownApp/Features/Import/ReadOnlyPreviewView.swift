//
//  ReadOnlyPreviewView.swift
//  MarkdownApp
//
//  只读的 Markdown 预览页，独立成一个可关闭的模态屏。
//  用于「导入预览」这类临时查看外部文件的场景——只看不改，也不落库。
//  渲染仍复用 WebPreviewView，不重复造预览逻辑（DRY）。
//

import SwiftUI

struct ReadOnlyPreviewView: View {
    let title: String
    let markdown: String

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WebPreviewView(markdown: markdown, colorScheme: colorScheme)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") { dismiss() }
                    }
                }
        }
    }
}
