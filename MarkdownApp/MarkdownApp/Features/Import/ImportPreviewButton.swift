//
//  ImportPreviewButton.swift
//  MarkdownApp
//
//  「打开文件预览」工具栏按钮：自包含地承载 .fileImporter 与只读预览 sheet。
//  独立成一个组件，让 FileBrowserView 只管浏览，导入这件事收敛在这里（SRP）。
//  这是「只读预览」路径——选中外部文件直接看，不拷进 App 目录（拷入导入是 S6 的事）。
//

import SwiftUI
import UniformTypeIdentifiers

struct ImportPreviewButton: View {
    let store: FileStore

    @State private var importing = false
    @State private var document: ImportedDocument?
    @State private var errorMessage: String?

    var body: some View {
        Button {
            importing = true
        } label: {
            Label("打开文件预览", systemImage: "doc.text.magnifyingglass")
        }
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: Self.allowedTypes,
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .sheet(item: $document) { doc in
            ReadOnlyPreviewView(title: doc.title, markdown: doc.markdown)
        }
        .alert("无法打开文件", isPresented: errorBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - 逻辑

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            guard let text = store.readExternalText(at: url) else {
                errorMessage = "读取文件内容失败，可能没有访问权限或不是文本文件。"
                return
            }
            document = ImportedDocument(
                title: url.deletingPathExtension().lastPathComponent,
                markdown: text
            )
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    // 允许 Markdown 与纯文本；markdown UTI 在部分系统未内建，故按扩展名兜底。
    private static let allowedTypes: [UTType] = {
        var types: [UTType] = [.plainText, .text]
        if let md = UTType(filenameExtension: "md") { types.append(md) }
        if let markdown = UTType("net.daringfireball.markdown") { types.append(markdown) }
        return types
    }()
}

/// 被选中、待只读预览的外部文档。
struct ImportedDocument: Identifiable {
    let id = UUID()
    let title: String
    let markdown: String
}
