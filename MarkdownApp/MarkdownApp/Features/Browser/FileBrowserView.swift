//
//  FileBrowserView.swift
//  MarkdownApp
//
//  单个目录的文件浏览器：文件夹点击进入下一级（无限嵌套），
//  右上角「+」新建文件夹/文档，左滑可移动/重命名/删除（纯图标）。
//

import SwiftUI

struct FileBrowserView: View {
    let store: FileStore
    let directory: URL
    /// 是否为根目录（根用「文档」作标题）。
    var isRoot: Bool = false

    @State private var nodes: [DocumentNode] = []
    @State private var sheet: BrowserSheet?
    @State private var pendingDelete: DocumentNode?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if nodes.isEmpty {
                ContentUnavailableView(
                    "空目录",
                    systemImage: "folder",
                    description: Text("点击右上角 + 新建文件夹或文档")
                )
            } else {
                List {
                    ForEach(nodes) { node in
                        row(for: node)
                    }
                }
            }
        }
        .navigationTitle(isRoot ? "文档" : directory.lastPathComponent)
        .navigationBarTitleDisplayMode(isRoot ? .large : .inline)
        .toolbar {
            addMenu
            // 「打开文件预览」只在根目录露出，是个全局动作（只读预览外部文件）。
            if isRoot {
                ToolbarItem(placement: .topBarTrailing) {
                    // 导入成功后刷新本目录列表（sheet 关闭不会触发 onAppear）。
                    ImportPreviewButton(store: store, onImported: reload)
                }
            }
        }
        .sheet(item: $sheet, content: sheetContent)
        .onAppear(perform: reload)
        .confirmationDialog(
            "确定删除「\(pendingDelete?.displayName ?? "")」？",
            isPresented: deleteBinding,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let node = pendingDelete { perform { try store.delete(node) } }
            }
        } message: {
            if pendingDelete?.isFolder == true {
                Text("文件夹及其中所有内容都会被删除。")
            }
        }
        .alert("操作失败", isPresented: errorBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - 行

    @ViewBuilder
    private func row(for node: DocumentNode) -> some View {
        // 文件夹下钻子目录，Markdown 文件下钻预览页；分流在 ContentView 的 navigationDestination。
        NavigationLink(value: node) { label(for: node) }
        // 三个动作只用图标（labelStyle(.iconOnly) 保留 VoiceOver 文案），配色区分：
        // 删除=红(destructive) / 重命名=蓝 / 移动=靛。
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { pendingDelete = node } label: {
                Label("删除", systemImage: "trash").labelStyle(.iconOnly)
            }
            Button { sheet = .rename(node) } label: {
                Label("重命名", systemImage: "square.and.pencil").labelStyle(.iconOnly)
            }
            .tint(.blue)
            Button { sheet = .move(node) } label: {
                Label("移动", systemImage: "folder.fill").labelStyle(.iconOnly)
            }
            .tint(.indigo)
        }
    }

    private func label(for node: DocumentNode) -> some View {
        Label(node.displayName, systemImage: node.systemImage)
            .font(Theme.mono())
    }

    // MARK: - 工具栏

    private var addMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { sheet = .newFolder } label: {
                    Label("新建文件夹", systemImage: "folder.badge.plus")
                }
                Button { sheet = .newMarkdown } label: {
                    Label("新建文档", systemImage: "doc.badge.plus")
                }
            } label: {
                Image(systemName: "plus")
            }
        }
    }

    // MARK: - Sheet 内容

    @ViewBuilder
    private func sheetContent(_ sheet: BrowserSheet) -> some View {
        switch sheet {
        case .newFolder:
            NameInputSheet(title: "新建文件夹", placeholder: "文件夹名称") { name in
                perform { _ = try store.createFolder(named: name, in: directory) }
            }
        case .newMarkdown:
            NameInputSheet(title: "新建文档", placeholder: "文档名称") { name in
                perform { _ = try store.createMarkdown(named: name, in: directory) }
            }
        case .rename(let node):
            NameInputSheet(title: "重命名", placeholder: "新名称", initialName: node.displayName) { name in
                perform { _ = try store.rename(node, to: name) }
            }
        case .move(let node):
            DirectoryPicker(
                store: store,
                title: "移动到",
                promptPrefix: "移动「\(node.displayName)」到",
                confirmLabel: "移动到此处",
                isDisabled: moveDisabled(for: node)
            ) { targetDir in
                // 移到原目录 = 无操作，避免 move() 因重名把自己复制成「name 2」。
                let currentParent = node.url.deletingLastPathComponent().standardizedFileURL
                guard targetDir.standardizedFileURL != currentParent else { return }
                _ = try store.move(node, to: targetDir)
                reload()
            }
        }
    }

    /// 移动时禁止把文件夹放进它自己或其子目录（否则会造成循环/丢失）。文件无子树，永不禁用。
    private func moveDisabled(for node: DocumentNode) -> (URL) -> Bool {
        { url in
            guard node.isFolder else { return false }
            let target = url.standardizedFileURL.path
            let selfPath = node.url.standardizedFileURL.path
            return target == selfPath || target.hasPrefix(selfPath + "/")
        }
    }

    // MARK: - 逻辑

    private func reload() {
        nodes = store.contents(of: directory)
    }

    /// 执行一次会修改磁盘的操作，成功后刷新列表，失败则记录错误。
    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 绑定

    private var deleteBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }
    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}

/// 浏览器可能弹出的 sheet 种类。
enum BrowserSheet: Identifiable {
    case newFolder
    case newMarkdown
    case rename(DocumentNode)
    case move(DocumentNode)

    var id: String {
        switch self {
        case .newFolder: "newFolder"
        case .newMarkdown: "newMarkdown"
        case .rename(let node): "rename-\(node.id.path)"
        case .move(let node): "move-\(node.id.path)"
        }
    }
}
