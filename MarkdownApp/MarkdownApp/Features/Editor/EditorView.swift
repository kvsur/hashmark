//
//  EditorView.swift
//  MarkdownApp
//
//  纯文本 Markdown 编辑器：等宽字体的原生 TextEditor。
//  受控组件——只接一个 @Binding 文本，不关心从哪加载、何时保存（那是 DocumentView 的事）。
//  MVP 阶段用 SwiftUI TextEditor；将来若需查找替换/大文档性能/精细光标控制，
//  可在此内部替换为 UIViewRepresentable 包 UITextView，对外接口不变。
//

import SwiftUI

struct EditorView: View {
    @Binding var text: String

    var body: some View {
        TextEditor(text: $text)
            .font(Theme.mono())
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)   // Markdown 源码不该自动大写
            .scrollContentBackground(.hidden)      // 隐藏默认背景，露出系统底色
            // 只加左右内边距（类似 web padding:0 12px）。不加上下：底部要让内容滚到
            // 工具栏下方形成半透明浮动效果，加了下边距会顶出空隙、破坏该效果。
            .padding(.horizontal, 12)
    }
}
