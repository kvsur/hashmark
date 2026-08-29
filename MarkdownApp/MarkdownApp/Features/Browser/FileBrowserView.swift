//
//  FileBrowserView.swift
//  MarkdownApp
//
//  单个目录的文件浏览器：文件夹点击进入下一级（无限嵌套），
//  右上角「+」新建文件夹/文档，左滑可移动/重命名/删除（纯图标）。
//

import SwiftUI

struct FileBrowserView: View {
    @EnvironmentObject private var documentLibrary: DocumentLibraryController
    let directory: URL
    /// 是否为根目录（根用「文档」作标题）。
    var isRoot: Bool = false
    /// 外部导入刷新信号：值变化即重载本目录。用于「分享/打开方式」导入后刷新首页
    /// （该预览由 ContentView 弹出，sheet 关闭不会触发本视图的 onAppear）。仅根目录接线。
    /// 放在 onOpenDocument 之前，让闭包参数保持在末位，ContentView 可用尾随闭包传入。
    var reloadToken: Int = 0
    /// 生成新文档后请求打开它（导航栈由上层 ContentView 持有）。仅根目录使用。
    var onOpenDocument: ((DocumentNode) -> Void)? = nil

    @State private var nodes: [DocumentNode] = []
    @State private var sheet: BrowserSheet?
    @State private var pendingDelete: DocumentNode?
    @State private var errorMessage: String?
    /// 设置页开关（仅根目录露出入口）。
    @State private var showingSettings = false

    // 首页 AI 写作入口（仅根目录）：过配置门槛后弹 AI 会话，接受即新建文档并打开。
    private let aiConfigStore = AIConfigStore()
    @State private var aiTrigger = false
    @State private var aiLaunch: AILaunch?

    var body: some View {
        Group {
            if nodes.isEmpty {
                AppEmptyStateView("Empty Folder", systemImage: "folder") {
                    Text("Tap + in the top right to create a folder or document")
                }
            } else {
                List {
                    ForEach(nodes) { node in
                        row(for: node)
                    }
                }
            }
        }
        // 根标题是本地化文案、子目录标题是用户自己的文件夹名（绝不可翻译），
        // 两者要走同一个 String 参数，故根标题需显式取词——必须用 LocalizationController.string，
        // 直接用 String(localized:) 会绕过取词拦截、永远显示系统语言。
        .navigationTitle(isRoot ? LocalizationController.string("Documents") : directory.lastPathComponent)
        .navigationBarTitleDisplayMode(isRoot ? .large : .inline)
        .toolbar {
            // 设置入口：全局动作，只在根目录左上角露出。
            if isRoot {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: {
                        Label("Settings", systemImage: "gearshape").labelStyle(.iconOnly)
                    }
                }
            }
            addMenu
            // 「打开文件预览」只在根目录露出，是个全局动作（只读预览外部文件）。
            if isRoot {
                ToolbarItem(placement: .topBarTrailing) {
                    // 导入成功后刷新本目录列表（sheet 关闭不会触发 onAppear）。
                    ImportPreviewButton(onImported: reload)
                }
            }
        }
        .sheet(item: $sheet, content: sheetContent)
        .sheet(isPresented: $showingSettings) { SettingsView() }
        // 首页大号 AI 入口：悬浮在底部（仅根目录），比工具栏按钮显著。
        .safeAreaInset(edge: .bottom) {
            if isRoot {
                HomeAIButton { aiTrigger = true }
                    .padding(.bottom, 8)
            }
        }
        // AI 门槛：配置齐全才进入会话，否则提示并可跳配置页。
        .aiConfigGate(trigger: $aiTrigger, store: aiConfigStore) { config in
            aiLaunch = AILaunch(config: config, action: .custom)
        }
        .sheet(item: $aiLaunch) { launch in
            // 首页生成整篇：无上下文、自由 prompt、允许反问。
            AIWritingView(config: launch.config, action: launch.action, context: nil, title: "AI Writing") { result in
                createDocument(from: result)
            }
        }
        .onAppear(perform: reload)
        .reloadsOnLibraryRevision(documentLibrary.revision, perform: reload)
        // 外部导入完成后由上层递增 reloadToken，触发首页列表刷新。
        .onChange(of: reloadToken) { _ in reload() }
        .alert("Action Failed", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - 行

    @ViewBuilder
    private func row(for node: DocumentNode) -> some View {
        // 文件夹下钻子目录，Markdown 文件下钻预览页；分流在 ContentView 的 navigationDestination。
        NavigationLink(value: node) {
            BrowserNodeLabel(node: node)
        }
        // 三个动作只用图标（labelStyle(.iconOnly) 保留 VoiceOver 文案），配色区分：
        // 删除=红 / 重命名=蓝 / 移动=靛。
        // 删除按钮不用 role:.destructive：否则 List 会在点击时自动播放「行滑出删除」动画，
        // 而我们只是先弹确认、并没真删，行滑出又弹回是多余的抖动。用 .tint(.red) 保持红色。
        // allowsFullSwipe:false 避免整行全滑直接触发删除确认。
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button { pendingDelete = node } label: {
                Label("Delete", systemImage: "trash").labelStyle(.iconOnly)
            }
            .tint(.red)
            Button { sheet = .rename(node) } label: {
                Label("Rename", systemImage: "pencil").labelStyle(.iconOnly)
            }
            .tint(.blue)
            Button { sheet = .move(node) } label: {
                Label("Move", systemImage: "folder").labelStyle(.iconOnly)
            }
            .tint(.indigo)
        }
        // 确认框挂在「行」上而非整个 List：以 popover 呈现时（iPad）才能锚定到被滑动的这一行，
        // 否则会固定锚在列表顶部。用「当前行是否为待删除项」控制各行自己的弹出。
        .confirmationDialog(
            "Delete “\(node.displayName)”?",
            isPresented: deleteBinding(for: node),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                perform { try await documentLibrary.delete(node) }
            }
        } message: {
            if node.isFolder {
                Text("The folder and everything inside it will be deleted.")
            }
        }
    }

    // MARK: - 工具栏

    private var addMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { sheet = .newFolder } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                Button { sheet = .newMarkdown } label: {
                    Label("New Document", systemImage: "doc.badge.plus")
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
            NameInputSheet(title: "New Folder", placeholder: "Folder name") { name in
                perform { _ = try await documentLibrary.createFolder(named: name, in: directory) }
            }
        case .newMarkdown:
            NameInputSheet(title: "New Document", placeholder: "Document name") { name in
                perform { _ = try await documentLibrary.createMarkdown(named: name, in: directory) }
            }
        case .rename(let node):
            NameInputSheet(title: "Rename", placeholder: "New name", initialName: node.displayName) { name in
                perform { _ = try await documentLibrary.rename(node, to: name) }
            }
        case .move(let node):
            DirectoryPicker(
                rootURL: documentLibrary.activeRootURL,
                title: "Move To",
                prompt: "Move “\(node.displayName)” to",
                confirmLabel: "Move Here",
                isDisabled: moveDisabled(for: node)
            ) { targetDir in
                // 移到原目录 = 无操作，避免 move() 因重名把自己复制成「name 2」。
                let currentParent = node.url.deletingLastPathComponent().standardizedFileURL
                guard targetDir.standardizedFileURL != currentParent else { return }
                _ = try await documentLibrary.move(node, to: targetDir)
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
        Task {
            do {
                nodes = try await documentLibrary.contents(of: directory)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// AI 生成整篇被接受：以内容首行推断文件名，新建 .md 写入并请求打开。
    private func createDocument(from content: String) {
        Task {
            do {
                let url = try await documentLibrary.createMarkdown(
                    named: Self.suggestedName(from: content),
                    in: directory
                )
                try await documentLibrary.writeText(content, to: url)
                reload()
                onOpenDocument?(DocumentNode(url: url, kind: .markdown, modifiedAt: .now))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// 从生成内容里取第一段有意义的文字作文件名（去掉 Markdown 标题/列表前缀，限长）；无则兜底。
    private static func suggestedName(from content: String) -> String {
        for raw in content.split(separator: "\n") {
            var line = raw.trimmingCharacters(in: .whitespaces)
            line = line.replacingOccurrences(of: "^[#>\\-\\*\\s]+", with: "", options: .regularExpression)
            line = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            return String(line.prefix(40))
        }
        // 兜底文件名：会落到用户的文档库里，故按当前界面语言取词。
        return LocalizationController.string("AI Writing")
    }

    /// 执行一次会修改磁盘的操作，成功后刷新列表，失败则记录错误。
    private func perform(_ action: @escaping () async throws -> Void) {
        Task {
            do {
                try await action()
                reload()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - 绑定

    /// 每行一个：只有「待删除项恰好是本行」时才为 true，关闭时清空。
    private func deleteBinding(for node: DocumentNode) -> Binding<Bool> {
        Binding(
            get: { pendingDelete?.id == node.id },
            set: { if !$0 { pendingDelete = nil } }
        )
    }
    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
