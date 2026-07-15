//
//  DirectoryPicker.swift
//  MarkdownApp
//
//  通用「选择目录」弹层：目录栈下钻 + 上一级 + 新建文件夹，确认后回调选中的目录 URL。
//  由「导入外部文件」（ImportTargetPicker）与「移动节点」（FileBrowserView）共用，
//  遵循 CLAUDE.md 的 DRY：选目录逻辑只写一处，各调用方只描述「确认时做什么」。
//
//  不复用完整 FileBrowserView（那里带预览下钻/滑动动作，用在选择器里过重），
//  这里用一个轻量目录栈自己下钻。
//

import SwiftUI

struct DirectoryPicker: View {
    let store: FileStore
    /// 导航标题。
    let title: LocalizedStringKey
    /// 头部提示短语，如「移动「x」到」「导入「x」到」；当前路径由本组件另起一行显示。
    let prompt: LocalizedStringKey
    /// 确认按钮文案，如「导入到此处」「移动到此处」。
    let confirmLabel: LocalizedStringKey
    /// 判断某目录是否禁止进入/选为目标（移动文件夹时排除自身及其子目录）。默认全部可选。
    let isDisabled: (URL) -> Bool
    /// 确认时执行的操作（导入/移动）：抛错则内部弹「操作失败」提示并保持打开；成功后自动关闭。
    let confirm: (URL) throws -> Void

    @Environment(\.dismiss) private var dismiss
    /// 目录栈：首元素恒为根目录，末元素为当前所在目录。
    @State private var stack: [URL]
    @State private var showNewFolder = false
    @State private var errorMessage: String?

    init(
        store: FileStore,
        title: LocalizedStringKey,
        prompt: LocalizedStringKey,
        confirmLabel: LocalizedStringKey,
        isDisabled: @escaping (URL) -> Bool = { _ in false },
        confirm: @escaping (URL) throws -> Void
    ) {
        self.store = store
        self.title = title
        self.prompt = prompt
        self.confirmLabel = confirmLabel
        self.isDisabled = isDisabled
        self.confirm = confirm
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
                            Label("Up One Level", systemImage: "arrow.up.left")
                        }
                    }
                    if subfolders.isEmpty {
                        Text("No subfolders")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(subfolders) { folder in
                            Button {
                                stack.append(folder.url)
                            } label: {
                                Label(folder.displayName, systemImage: "folder.fill")
                                    .font(Theme.mono())
                            }
                            .disabled(isDisabled(folder.url))
                        }
                    }
                } header: {
                    // 提示短语与当前路径分两行渲染，而不是拼成一个「%@：%@」的 key——
                    // 拼接会把语序和标点写死（「：」是中文标点，德/俄该用「: 」），无法正确翻译。
                    VStack(alignment: .leading, spacing: 2) {
                        Text(prompt)
                        Text(verbatim: currentPathText)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                // 新建文件夹：没有合适目录时可当场建一个（建完自动进入）。
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNewFolder = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                }
                // 主操作放底部，醒目且不与右上角新建冲突。
                ToolbarItem(placement: .bottomBar) {
                    Button(confirmLabel, action: performConfirm)
                        .disabled(isDisabled(currentDir))
                }
            }
            .sheet(isPresented: $showNewFolder) {
                NameInputSheet(title: "New Folder", placeholder: "Folder name") { name in
                    createFolder(named: name)
                }
            }
            .alert("Action Failed", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .rebuildsOnLanguageChange()
    }

    // MARK: - 逻辑

    /// 当前目录的可读路径：根显示本地化的「文档」，其余是用户自己的目录名（不翻译），以「/」连接。
    private var currentPathText: String {
        let names = stack.enumerated().map { index, url in
            index == 0 ? LocalizationController.string("Documents") : url.lastPathComponent
        }
        return names.joined(separator: " / ")
    }

    private func createFolder(named name: String) {
        do {
            let url = try store.createFolder(named: name, in: currentDir)
            stack.append(url) // 建完直接进入，方便当场导入/移动到它
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performConfirm() {
        do {
            try confirm(currentDir)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
