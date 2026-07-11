//
//  DocumentView.swift
//  MarkdownApp
//
//  单篇文档的「屏」：承载预览/编辑两种模式并管理文本的加载与保存。
//  它是本屏的唯一数据源（text），把「怎么渲染」交给 WebPreviewView、
//  「怎么编辑」交给 EditorView，自己只负责协调：读盘、切模式、写盘。
//
//  类比前端：这相当于一个页面级容器组件，持有 state 并把只读视图与编辑视图组合起来，
//  子组件都是受控的。
//

import SwiftUI

struct DocumentView: View {
    let store: FileStore
    let node: DocumentNode

    /// 两种模式：预览（渲染）/ 编辑（源码）。
    enum Mode: String, CaseIterable, Identifiable {
        case preview, edit
        var id: String { rawValue }
        var label: String { self == .preview ? "预览" : "编辑" }
    }

    @Environment(\.colorScheme) private var colorScheme
    @State private var text: String = ""
    /// 上次已写入磁盘的内容，用来判断是否有未保存改动（脏检查）。
    @State private var savedText: String = ""
    @State private var mode: Mode = .preview
    @State private var loaded = false

    var body: some View {
        content
            .navigationTitle(node.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("模式", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    // 给整个控件固定宽度让两段均分加宽；比给段内 Text 加 padding 更稳，
                    // 后者会和 UISegmentedControl 的选中胶囊布局打架、显得歪。
                    .frame(width: 200)
                }
            }
            .onAppear(perform: loadIfNeeded)
            // 切回预览时先落盘，保证预览读到的是最新且已持久化的内容。
            .onChange(of: mode) { _, newMode in
                if newMode == .preview { save() }
            }
            .onDisappear(perform: save)
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .preview:
            WebPreviewView(markdown: text, colorScheme: colorScheme)
                .ignoresSafeArea(edges: .bottom)
        case .edit:
            EditorView(text: $text)
        }
    }

    // MARK: - 逻辑

    /// 首次出现时从磁盘读入一次；之后 text 即本屏数据源，不再重复读盘。
    private func loadIfNeeded() {
        guard !loaded else { return }
        text = store.readText(at: node.url)
        savedText = text
        loaded = true
    }

    /// 有改动才写盘，避免无谓 IO 与修改时间抖动。
    private func save() {
        guard loaded, text != savedText else { return }
        try? store.writeText(text, to: node.url)
        savedText = text
    }
}
