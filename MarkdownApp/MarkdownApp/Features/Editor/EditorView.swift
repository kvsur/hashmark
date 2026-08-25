//
//  EditorView.swift
//  MarkdownApp
//
//  纯文本 Markdown 编辑器：等宽字体的源码编辑区。
//  受控组件——只接一个 @Binding 文本，不关心从哪加载、何时保存（那是 DocumentView 的事）。
//  内部由 MarkdownTextView（UITextView 封装）承载，替代早期的 SwiftUI TextEditor：
//  这样才拿得到「选区气泡菜单」与「文本布局 rect」，为「选中 → AI 润色」「跟随光标行选块」铺底座。
//  对外接口保持不变：EditorView(text: $text)，另可选传入「选区请求 AI」回调，DocumentView 用它接润色链路。
//

import SwiftUI

struct EditorView: View {
    @Binding var text: String
    var handle: EditorHandle? = nil
    /// 选区气泡菜单点「AI」时回调（选中文本 + range）；默认空，纯预览等场景可不接。
    var onRequestAIRefine: (_ selectedText: String, _ range: NSRange) -> Void = { _, _ in }

    var body: some View {
        MarkdownTextView(text: $text, handle: handle, onRequestAIRefine: onRequestAIRefine)
    }
}
