//
//  DocumentReferencePicker.swift
//  MarkdownApp
//
//  引用库内文档作为 AI 参考上下文：半屏弹层里用可折叠树多选 .md 文档。
//  与 DocumentSwitcherSheet 的区别——那里是「点一篇就切换」，这里是「勾选多篇作参考」。
//  确认时把选中文档读成文本、跳过空/不可读的，回传为 documentReference 附件。
//  文件夹只作折叠展示、不可选；已在附件条里的文档进来时预勾选，避免重复添加。
//

import SwiftUI

struct DocumentReferencePicker: View {
    @EnvironmentObject private var documentLibrary: DocumentLibraryController
    /// 已在附件条里的引用文档 URL，进来预勾选（去重）。
    let alreadySelected: Set<URL>
    /// 确认回调：交出选中文档对应的 documentReference 附件（已读文本、跳过空/不可读）。
    let onConfirm: ([AIAttachment]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var roots: [DocumentTreeNode] = []
    @State private var selected: Set<URL> = []

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
            .navigationTitle("Reference a Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { confirm() }
                        .bold()
                        .disabled(selected.isEmpty)
                }
            }
            .onAppear {
                selected = alreadySelected
                reload()
            }
            .reloadsOnLibraryRevision(documentLibrary.revision, perform: reload)
        }
        .presentationDetents([.medium, .large])
        .rebuildsOnLanguageChange()
    }

    private func reload() {
        Task { roots = (try? await documentLibrary.tree()) ?? [] }
    }

    @ViewBuilder
    private func row(for item: DocumentTreeNode) -> some View {
        if item.isFolder {
            // 文件夹：仅展示，点击由 OutlineGroup 负责折叠/展开，不参与选择。
            Label(item.node.displayName, systemImage: "folder.fill")
                .font(Theme.mono())
        } else {
            let isOn = selected.contains(item.node.url)
            Button {
                toggle(item.node.url)
            } label: {
                Label {
                    Text(item.node.displayName)
                        .foregroundStyle(.primary)
                } icon: {
                    // 勾选态用实心对勾，未选用空心圈——对齐系统多选语义。
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                }
                .font(Theme.mono())
            }
        }
    }

    private func toggle(_ url: URL) {
        Haptics.light()
        if selected.contains(url) {
            selected.remove(url)
        } else {
            selected.insert(url)
        }
    }

    /// 把选中的文档读成文本、跳过空/不可读的，回传为附件。
    private func confirm() {
        Task {
            let attachments = await DocumentReferenceResolver.attachments(
                in: roots,
                selectedURLs: selected,
                readText: { try await documentLibrary.readText(at: $0) }
            )
            onConfirm(attachments)
            dismiss()
        }
    }
}
