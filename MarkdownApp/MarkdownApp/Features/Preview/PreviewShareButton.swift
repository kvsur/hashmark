//
//  PreviewShareButton.swift
//  MarkdownApp
//
//  「分享」按钮：按传入的动作集合展示选项，调用方按场景决定给哪些。
//  预览态：长截图 / 纯文本 / PDF（都依赖已渲染的 WebView）；
//  编辑态：源文件(.md) / 源内容(Markdown)（只依赖文本与磁盘文件）。
//  DocumentView 两态与 ReadOnlyPreviewView 共用同一按钮（DRY）。
//

import SwiftUI

struct PreviewShareButton: View {
    /// 当前文档的 Markdown 源文本，用于「源内容」分享。
    let markdown: String
    /// 源文件 URL；「源文件」选项与 PDF 文件名依赖它，为 nil 时不显示「源文件」。
    var sourceURL: URL? = nil
    /// 取底层 WebView 做长截图/纯文本/PDF 的桥。
    let handle: PreviewHandle
    /// 要展示的分享动作（按此顺序渲染）。
    let actions: [ShareAction]

    /// 分享动作种类。无关联值，天然可 Hashable，供 ForEach 用。
    enum ShareAction {
        case longScreenshot
        case plainText
        case pdf
        case sourceFile
        case sourceContent
    }

    @State private var showDialog = false
    @State private var shareItems: ShareItems?
    /// 长截图/PDF 生成可能耗时，期间以转圈替代图标并禁用按钮。
    @State private var isBusy = false

    var body: some View {
        Button {
            showDialog = true
        } label: {
            if isBusy {
                ProgressView()
            } else {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .disabled(isBusy)
        .confirmationDialog("分享", isPresented: $showDialog, titleVisibility: .visible) {
            ForEach(actions, id: \.self) { action in
                button(for: action)
            }
        }
        .sheet(item: $shareItems) { payload in
            ShareSheet(items: payload.items)
        }
    }

    @ViewBuilder
    private func button(for action: ShareAction) -> some View {
        switch action {
        case .longScreenshot:
            Button("长截图") { shareLongScreenshot() }
        case .plainText:
            Button("纯文本") { sharePlainText() }
        case .pdf:
            Button("PDF") { sharePDF() }
        case .sourceFile:
            if let sourceURL {
                Button("源文件（.md）") { shareItems = ShareItems(items: [sourceURL]) }
            }
        case .sourceContent:
            Button("源内容（Markdown）") { shareItems = ShareItems(items: [markdown]) }
        }
    }

    private func shareLongScreenshot() {
        isBusy = true
        handle.captureLongScreenshot { image in
            isBusy = false
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

    /// PDF：把整篇渲染内容导出为 PDF，写入临时文件后分享（文件名取源文件名）。
    private func sharePDF() {
        isBusy = true
        handle.exportPDF { data in
            isBusy = false
            guard let data else { return }
            let base = sourceURL?.deletingPathExtension().lastPathComponent ?? "文档"
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(base).appendingPathExtension("pdf")
            guard (try? data.write(to: url, options: .atomic)) != nil else { return }
            shareItems = ShareItems(items: [url])
        }
    }
}
