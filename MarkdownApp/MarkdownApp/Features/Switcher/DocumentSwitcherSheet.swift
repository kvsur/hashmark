//
//  DocumentSwitcherSheet.swift
//  MarkdownApp
//
//  文档快速切换器（S10）：半屏弹层里用可折叠树展示全部目录/文档。
//  与首页浏览器不同——这里点文件夹是「就地折叠/展开」，不下钻二级页；
//  点文档则回调选中并关闭，用于在编辑/预览时快速切到另一篇。
//

import SwiftUI

struct DocumentSwitcherSheet: View {
    @EnvironmentObject private var documentLibrary: DocumentLibraryController
    /// 当前正在查看的文档 URL，用来在树里高亮。
    let currentURL: URL
    /// 选中某文档时回调（回调后本弹层关闭）。
    let onSelect: (DocumentNode) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var roots: [DocumentTreeNode] = []

    var body: some View {
        NavigationStack {
            Group {
                if roots.isEmpty {
                    AppEmptyStateView("No Documents", systemImage: "folder") {
                        Text("Create a document on the home screen first")
                    }
                } else {
                    List {
                        OutlineGroup(roots, children: \.children) { item in
                            row(for: item)
                        }
                    }
                }
            }
            .navigationTitle("Switch Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: reload)
            .reloadsOnLibraryRevision(documentLibrary.revision, perform: reload)
        }
        .rebuildsOnLanguageChange()
    }

    private func reload() {
        Task { roots = (try? await documentLibrary.tree()) ?? [] }
    }

    @ViewBuilder
    private func row(for item: DocumentTreeNode) -> some View {
        if item.isFolder {
            // 文件夹：只作展示，点击由 OutlineGroup 负责折叠/展开。
            Label(item.node.displayName, systemImage: "folder.fill")
                .font(Theme.mono())
        } else {
            let isCurrent = item.node.url == currentURL
            Button {
                onSelect(item.node)
                dismiss()
            } label: {
                Label {
                    Text(item.node.displayName)
                } icon: {
                    Image(systemName: isCurrent ? "doc.text.fill" : "doc.text")
                }
                .font(Theme.mono())
                .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
            }
        }
    }
}
