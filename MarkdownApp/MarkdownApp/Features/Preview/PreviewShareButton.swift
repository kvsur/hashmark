//
//  PreviewShareButton.swift
//  MarkdownApp
//
//  预览态右上角「分享」按钮：长截图 / 源文件 / 源内容（Markdown）/ 纯文本。
//  DocumentView 与 ReadOnlyPreviewView 共用同一套分享入口（DRY）。
//

import SwiftUI

struct PreviewShareButton: View {
    /// 当前文档的 Markdown 源文本，用于「源内容」分享。
    let markdown: String
    /// 源文件 URL；为 nil 时不显示「源文件」选项（如无对应磁盘文件的场景）。
    var sourceURL: URL? = nil
    /// 取底层 WebView 做长截图的桥。
    let handle: PreviewHandle

    @State private var showDialog = false
    @State private var shareItems: ShareItems?
    /// 长截图分片拼接可能耗时数秒，期间以转圈替代图标并禁用按钮。
    @State private var isCapturing = false

    var body: some View {
        Button {
            showDialog = true
        } label: {
            if isCapturing {
                ProgressView()
            } else {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .disabled(isCapturing)
        .confirmationDialog("分享", isPresented: $showDialog, titleVisibility: .visible) {
            Button("长截图") { shareLongScreenshot() }
            if let sourceURL {
                Button("源文件") { shareItems = ShareItems(items: [sourceURL]) }
            }
            Button("源内容（Markdown）") { shareItems = ShareItems(items: [markdown]) }
            Button("纯文本") { sharePlainText() }
        }
        .sheet(item: $shareItems) { payload in
            ShareSheet(items: payload.items)
        }
    }

    private func shareLongScreenshot() {
        isCapturing = true
        handle.captureLongScreenshot { image in
            isCapturing = false
            guard let image else { return }
            shareItems = ShareItems(items: [image])
        }
    }

    /// 纯文本：分享去掉 Markdown 语法标记后的渲染可见文字；取不到时退回源内容。
    private func sharePlainText() {
        handle.extractPlainText { text in
            shareItems = ShareItems(items: [text ?? markdown])
        }
    }
}
