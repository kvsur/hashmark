//
//  ImportTargetPicker.swift
//  MarkdownApp
//
//  外部文件导入的「中间页」：让用户为传入的文件挑一个目标目录（默认根目录），
//  确认后把文件拷进 FileStore，并回调新文件 URL 供上层进入预览（S6.3/S6.4/S6.5）。
//
//  只做「选目录 + 触发导入」，不复用完整 FileBrowserView（那里还带新建/改名/删除，
//  用在选择器里过重）。这里用一个轻量的目录栈自己下钻。
//

import SwiftUI

struct ImportTargetPicker: View {
    let store: FileStore
    /// 待导入的外部文件 URL。
    let sourceURL: URL
    /// 导入成功后回调新文件 URL。
    let onImported: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    /// 目录栈：首元素恒为根目录，末元素为当前所在目录。
    @State private var stack: [URL]
    @State private var errorMessage: String?

    init(store: FileStore, sourceURL: URL, onImported: @escaping (URL) -> Void) {
        self.store = store
        self.sourceURL = sourceURL
        self.onImported = onImported
        _stack = State(initialValue: [store.rootURL])
    }

    private var currentDir: URL { stack.last ?? store.rootURL }
    private var subfolders: [DocumentNode] {
        store.contents(of: currentDir).filter(\.isFolder)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if stack.count > 1 {
                        Button {
                            stack.removeLast()
                        } label: {
                            Label("上一级", systemImage: "arrow.up.left")
                        }
                    }
                    if subfolders.isEmpty {
                        Text("没有子文件夹")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(subfolders) { folder in
                            Button {
                                stack.append(folder.url)
                            } label: {
                                Label(folder.displayName, systemImage: "folder.fill")
                                    .font(Theme.mono())
                            }
                        }
                    }
                } header: {
                    Text("导入「\(sourceURL.lastPathComponent)」到：\(currentPathText)")
                }
            }
            .navigationTitle("选择目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("导入到此处", action: performImport)
                }
            }
            .alert("导入失败", isPresented: errorBinding) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - 逻辑

    /// 当前目录的可读路径：根显示「文档」，其余用目录名以「/」连接。
    private var currentPathText: String {
        let names = stack.enumerated().map { index, url in
            index == 0 ? "文档" : url.lastPathComponent
        }
        return names.joined(separator: " / ")
    }

    private func performImport() {
        do {
            let newURL = try store.importFile(from: sourceURL, to: currentDir)
            dismiss()
            onImported(newURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}

/// 包装传入文件 URL，供 sheet(item:) 驱动导入中间页。
struct PendingImport: Identifiable {
    let id = UUID()
    let url: URL
}
