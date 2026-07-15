//
//  ReadOnlyPreviewView.swift
//  MarkdownApp
//
//  只读的 Markdown 预览页，独立成一个可关闭的模态屏。
//  用于「导入预览」这类临时查看外部文件的场景——只看不改。
//  渲染复用 WebPreviewView（DRY）。
//
//  S11：若预览的是「外部」文件（不在本 App 目录内），提供「导入」把它拷进来；
//  若本就是 App 目录内的文档（如经文件 App 浏览 Hashmark 目录打开），则不显示导入。
//

import SwiftUI

struct ReadOnlyPreviewView: View {
    let store: FileStore
    /// 被预览文件的原始 URL，用来判断是否可导入。
    let sourceURL: URL
    let title: String
    let markdown: String
    /// 导入成功后回调（供上层刷新文件列表）。
    var onImported: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var showImportPicker = false
    /// 桥接预览 WebView，供「分享 - 长截图」取用。
    @State private var previewHandle = PreviewHandle()

    /// 仅当文件不在本 App 目录内时才允许导入。
    private var canImport: Bool { !store.isInsideStore(sourceURL) }

    var body: some View {
        NavigationStack {
            MarkdownPreviewView(markdown: markdown, handle: previewHandle)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if canImport {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                showImportPicker = true
                            } label: {
                                Label("Import", systemImage: "square.and.arrow.down")
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        // 只读预览始终是渲染态：长截图/纯文本/PDF 与源文件/源内容都可用。
                        PreviewShareButton(
                            markdown: markdown,
                            sourceURL: sourceURL,
                            handle: previewHandle,
                            actions: [.longScreenshot, .plainText, .pdf, .sourceFile, .sourceContent]
                        )
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
                .sheet(isPresented: $showImportPicker) {
                    ImportTargetPicker(store: store, sourceURL: sourceURL) { _ in
                        // 导入成功：通知上层刷新列表，再关闭整个只读预览。
                        onImported()
                        dismiss()
                    }
                }
        }
        .rebuildsOnLanguageChange()
    }
}
