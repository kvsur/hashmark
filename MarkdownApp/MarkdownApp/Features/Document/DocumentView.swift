//
//  DocumentView.swift
//  MarkdownApp
//
//  单篇文档的「屏」：承载预览/编辑两种模式并管理文本的加载与保存。
//  它是本屏的唯一数据源（text），把「怎么渲染」交给 WebPreviewView、
//  「怎么编辑」交给 EditorView，自己只负责协调：读盘、切模式、写盘。
//
//  类比前端：这相当于一个页面级容器组件，持有 state 并把只读视图与编辑视图组合起来，
//  子组件都是受控的。
//

import SwiftUI

struct DocumentView: View {
    @EnvironmentObject private var documentLibrary: DocumentLibraryController
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    /// 当前文档与脏草稿。值类型状态配合快速切换器原地换文档（不改导航栈）。
    @State private var draft: DocumentDraft

    init(node: DocumentNode) {
        _draft = State(initialValue: DocumentDraft(node: node))
    }

    private var node: DocumentNode { draft.node }
    private var text: String { draft.text }

    /// 两种模式：预览（渲染）/ 编辑（源码）。
    enum Mode: String, CaseIterable, Identifiable {
        case preview, edit
        var id: String { rawValue }
        var label: LocalizedStringKey { self == .preview ? "Preview" : "Edit" }
    }

    @State private var mode: Mode = .preview
    @State private var showSwitcher = false
    /// 桥接预览 WebView，供预览态「分享 - 长截图」取用。
    @State private var previewHandle = PreviewHandle()
    @State private var editorHandle = EditorHandle()
    @State private var showOutline = false
    @State private var loadError: String?
    @State private var loadTask: Task<Void, Never>?
    @State private var openDocumentPresenter: OpenDocumentPresenter?
    @State private var documentEventTask: Task<Void, Never>?
    @State private var syncNotice: String?
    @State private var syncNoticeTask: Task<Void, Never>?
    @State private var deletionAlert: DocumentDeletionAlert?
    @State private var isBackingFileDeleted = false

    private struct DocumentDeletionAlert: Identifiable {
        let id = UUID()
        let message: String
        let retryURL: URL?
    }

    // AI 写作：点按钮先选动作，过配置门槛后弹会话，接受则应用回文档。
    private let aiConfigStore = AIConfigStore()
    @State private var showAIActions = false
    @State private var aiTrigger = false
    @State private var pendingAction: AIAction?
    @State private var aiLaunch: AILaunch?
    /// 选区润色态：非 nil 表示本次 AI 会话来自「选中文字 → 气泡菜单 AI」，接受时按此 range 回填。
    /// nil 表示走整篇动作（底栏 AI 按钮）。整篇路径会先把它清空，避免沿用上一次的选区。
    @State private var pendingSelection: EditorSelection?

    /// 一次选区润色所需的最小信息：选中文本 + 它在源码中的 NSRange。
    private struct EditorSelection {
        let range: NSRange
        let text: String
    }

    var body: some View {
        content
            // 预览左滑 → 编辑；编辑右滑 → 预览。方向判定与滚动/选择冲突收敛在封装里。
            // 触点落在预览内可横滚区（宽代码块/表格）时避让，保证内部横向滚动优先。
            .horizontalSwitch(
                onSwipeLeft: {
                    if mode == .preview, !previewHandle.isTouchingHorizontalScroller {
                        switchMode(to: .edit)
                    }
                },
                onSwipeRight: { if mode == .edit { switchMode(to: .preview) } }
            )
            .navigationTitle(node.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    // 走 switchMode 让「点分段控件」与「滑动切换」共用同一套过渡动画。
                    Picker("Mode", selection: Binding(get: { mode }, set: { switchMode(to: $0) })) {
                        ForEach(Mode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    // 给整个控件固定宽度让两段均分加宽；比给段内 Text 加 padding 更稳，
                    // 后者会和 UISegmentedControl 的选中胶囊布局打架、显得歪。
                    .frame(width: 200)
                }
                // 分享两态都有，但选项按模式区分：
                // 预览态=长截图/纯文本/PDF（依赖已渲染 WebView）+ 源文件/源内容（预览时也常要拿源码）；
                // 编辑态只给源文件/源内容（此时无已渲染 WebView，截图/PDF 无从生成）。
                ToolbarItem(placement: .topBarTrailing) {
                    PreviewShareButton(
                        markdown: text,
                        sourceURL: node.url,
                        handle: previewHandle,
                        actions: mode == .preview
                            ? [.longScreenshot, .plainText, .pdf, .sourceFile, .sourceContent]
                            : [.sourceFile, .sourceContent]
                    )
                }
                // 文档间/文档内导航组成左侧一组，AI 内容操作独立在右侧；版本布局差异由组件收敛。
                DocumentBottomToolbar {
                        switchDocButton
                        outlineButton
                } primaryAction: {
                        aiActionButton
                }
            }
            .aiConfigGate(trigger: $aiTrigger, store: aiConfigStore) { config in
                if let action = pendingAction {
                    // 把选区（若有）烘焙进 launch，后续都从 launch 读，不再读 @State。
                    aiLaunch = AILaunch(config: config, action: action,
                                        selectionText: pendingSelection?.text,
                                        selectionRange: pendingSelection?.range)
                }
            }
            .sheet(item: $aiLaunch) { launch in
                AIWritingView(
                    config: launch.config,
                    action: launch.action,
                    // 选区润色只把「选中文本」作为上下文；整篇动作用全文。
                    context: launch.selectionText ?? text,
                    // 选区润色时把选中内容展示给用户看；整篇动作不展示（内容即整篇，无需预览）。
                    contextPreview: launch.selectionText,
                    title: launch.action.label
                ) { result in
                    applyAI(launch, result)
                }
            }
            .onAppear(perform: loadIfNeeded)
            .onAppear(perform: configureOpenDocumentPresentation)
            .onAppear(perform: configureScrollSync)
            // 切回预览时先落盘，保证预览读到的是最新且已持久化的内容。
            .onChange(of: mode) { newMode in
                if newMode == .preview { save() }
                configureScrollSync()
            }
            .onChange(of: horizontalSizeClass) { _ in configureScrollSync() }
            .onChange(of: documentLibrary.storageMode) { _ in configureOpenDocumentPresentation() }
            .onChange(of: scenePhase) { phase in
                if phase == .active { configureOpenDocumentPresentation() }
                else { stopOpenDocumentPresentation() }
            }
            .onDisappear {
                loadTask?.cancel()
                documentEventTask?.cancel()
                syncNoticeTask?.cancel()
                stopOpenDocumentPresentation()
                if !isBackingFileDeleted { save() }
            }
            .overlay(alignment: .top) {
                if let syncNotice {
                    Text(syncNotice)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, 8)
                        .padding(.horizontal)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .accessibilityAddTraits(.isStaticText)
                }
            }
            .alert(item: $deletionAlert) { payload in
                if let retryURL = payload.retryURL {
                    return Alert(
                        title: Text("Recovery Needed"),
                        message: Text(payload.message),
                        primaryButton: .default(Text("Retry")) {
                            enqueueDocumentEvent(.deleted(retryURL))
                        },
                        secondaryButton: .cancel(Text("Keep Editing"))
                    )
                }
                return Alert(
                    title: Text("Document No Longer Available"),
                    message: Text(payload.message),
                    dismissButton: .default(Text("Close")) { dismiss() }
                )
            }
            .sheet(isPresented: $showSwitcher) {
                DocumentSwitcherSheet(currentURL: node.url) { selected in
                    switchTo(selected)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showOutline) {
                MarkdownOutlineSheet(markdown: text) { item in
                    navigate(to: item)
                }
                .presentationDetents([.medium, .large])
            }
    }

    // MARK: - 底栏按钮

    /// 「切换文档」按钮：仅图标（rectangle.stack 表意「多篇文档间切换」），略放大。
    private var switchDocButton: some View {
        Button {
            Haptics.light()   // 点击「切换文档」给一下反馈
            showSwitcher = true
        } label: {
            // 仅图标：直接用 Label，工具栏会自动呈现为 icon-only（accessibility 仍保留文字）。
            Label("Switch Document", systemImage: "rectangle.stack")
        }
        .controlSize(.large)
    }

    /// 文档内标题导航；与「切换文档」同属导航组，在 Preview/Edit 两态均可用。
    private var outlineButton: some View {
        Button { showOutline = true } label: {
            Label("Outline", systemImage: "list.bullet")
        }
        .controlSize(.large)
    }

    /// AI 辅助按钮：彩色 "AI" 文字 + sparkles 图标，点按弹出动作列表（锚定到本按钮）。
    private var aiActionButton: some View {
        AIAssistButton(title: "AI") { showAIActions = true }
            .controlSize(.large)
            // 弹层锚定到 AI 按钮本身：紧贴底部工具栏出现，而非飘到屏幕顶部。
            // compact 场景显式用 .popover 适配，保持「贴着按钮」的观感。
            .popover(isPresented: $showAIActions) {
                AIActionPopover { action in
                    pendingSelection = nil   // 整篇动作：清掉可能残留的选区态
                    pendingAction = action
                    showAIActions = false
                    // 延迟触发，确保 popover 关闭动画完成后再触发 AI 流程，
                    // 避免视图层级变化导致状态更新丢失。
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(100))
                        aiTrigger = true
                    }
                }
                .compatibleCompactPopover()
            }
    }

    @ViewBuilder
    private var content: some View {
        if !draft.isLoaded {
            if let loadError {
                AppEmptyStateView("Cannot Open File", systemImage: "icloud.slash") {
                    Text(loadError)
                } actions: {
                    HStack {
                        Button("Close") { dismiss() }
                        Button("Retry") { loadIfNeeded() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                ProgressView()
            }
        } else {
            switch mode {
            case .preview:
                MarkdownPreviewView(markdown: text, handle: previewHandle)
                    .ignoresSafeArea(edges: .bottom)
                    // 预览在「编辑的左边」：切走时向左滑出、回来时从左侧滑入。
                    .transition(.move(edge: .leading))
            case .edit:
                if horizontalSizeClass == .regular {
                    HStack(spacing: 0) {
                        EditorView(text: $draft.text, handle: editorHandle, onRequestAIRefine: requestSelectionRefine)
                            .frame(maxWidth: .infinity)
                        Divider()
                        MarkdownPreviewView(markdown: text, handle: previewHandle)
                            .frame(maxWidth: .infinity)
                    }
                    .transition(.move(edge: .trailing))
                } else {
                    EditorView(text: $draft.text, handle: editorHandle, onRequestAIRefine: requestSelectionRefine)
                        // 编辑在「预览的右边」：切走时向右滑出、进入时从右侧滑入。
                        .transition(.move(edge: .trailing))
                }
            }
        }
    }

    /// 带过渡动画地切换预览/编辑；同时驱动 content 的 move 过渡，形成左右分页观感。
    /// 落盘仍由 onChange(of: mode) 负责（切到预览时先保存），这里只管动画与状态。
    private func switchMode(to newMode: Mode) {
        guard mode != newMode else { return }
        Haptics.soft()   // 切换成功给一下细微反馈（点分段控件与滑动切换共用）
        withAnimation(.easeInOut(duration: 0.25)) { mode = newMode }
    }

    /// 同一份大纲按当前模式选择对应目标：源码聚焦标题，预览滚到渲染后的标题。
    private func navigate(to item: MarkdownOutlineItem) {
        switch mode {
        case .preview:
            previewHandle.scroll(
                toHeadingLevel: item.level,
                rawTitle: item.title,
                occurrence: item.occurrence
            )
        case .edit:
            editorHandle.focus(range: item.range)
        }
    }

    /// 仅 iPad 宽屏编辑态同时显示两栏时启用双向比例同步；其它布局解除闭包，避免隐藏视图互相驱动。
    private func configureScrollSync() {
        guard horizontalSizeClass == .regular, mode == .edit else {
            editorHandle.onScrollFraction = nil
            previewHandle.onScrollFraction = nil
            return
        }
        editorHandle.onScrollFraction = { [weak previewHandle = previewHandle] fraction in
            previewHandle?.scroll(toFraction: fraction)
        }
        previewHandle.onScrollFraction = { [weak editorHandle = editorHandle] fraction in
            editorHandle?.scroll(toFraction: fraction)
        }
    }

    // MARK: - AI

    /// 用户在编辑区选中文字、点气泡菜单「AI」时触发：以选中文本为上下文发起润色会话。
    /// 复用整篇 AI 的同一套门槛/会话机制（pendingAction + aiTrigger + aiConfigGate），只是额外记下选区。
    private func requestSelectionRefine(_ selectedText: String, _ range: NSRange) {
        guard !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Haptics.light()
        pendingSelection = EditorSelection(range: range, text: selectedText)
        pendingAction = .polish            // 选区快捷入口固定走「润色」
        aiTrigger = true                   // 过配置门槛后由 aiConfigGate 装配 aiLaunch 弹会话
    }

    /// 接受 AI 结果：按 launch 载荷应用到当前文档并落盘。
    /// 选区润色=只替换选中的那段 range（其余不动）；否则按动作——续写/自定义追加文末、润色/整理替换全文。
    private func applyAI(_ launch: AILaunch, _ result: String) {
        if let range = launch.selectionRange {
            applyToSelection(range, result)
            return
        }
        switch launch.action.editorApplyMode {
        case .append:
            draft.text = text.isEmpty ? result : text + "\n\n" + result
        case .replace:
            draft.text = result
        }
        save()
    }

    /// 按 range 回填选区润色结果。range 越界（理论上会话期间源文不可编辑，但仍防御）则不覆盖错内容，
    /// 安全退化为追加到文末。
    private func applyToSelection(_ range: NSRange, _ result: String) {
        let ns = text as NSString
        if range.location != NSNotFound, range.location >= 0, range.location + range.length <= ns.length {
            draft.text = ns.replacingCharacters(in: range, with: result)
        } else {
            draft.text = text.isEmpty ? result : text + "\n\n" + result
        }
        save()
    }

    // MARK: - 逻辑

    /// 首次出现时从磁盘读入一次；之后 text 即本屏数据源，不再重复读盘。
    private func loadIfNeeded() {
        guard !draft.isLoaded else { return }
        let url = node.url
        loadError = nil
        loadTask?.cancel()
        loadTask = Task {
            do {
                let loaded = try await documentLibrary.readText(at: url)
                guard !Task.isCancelled, node.url == url else { return }
                draft.loadIfNeeded(text: loaded)
            } catch is CancellationError {
                return
            } catch {
                loadError = error.localizedDescription
            }
        }
    }

    /// 有改动才写盘，避免无谓 IO 与修改时间抖动。
    private func save() {
        guard draft.isDirty, !isBackingFileDeleted else { return }
        let text = draft.text
        let url = node.url
        Task {
            guard (try? await documentLibrary.writeText(text, to: url)) != nil else { return }
            draft.markSaved(text, at: url)
        }
    }

    private func configureOpenDocumentPresentation() {
        stopOpenDocumentPresentation()
        guard documentLibrary.storageMode == .iCloud,
              scenePhase == .active,
              !isBackingFileDeleted else { return }
        let presenter = OpenDocumentPresenter(url: node.url) { event in
            Task { @MainActor in enqueueDocumentEvent(event) }
        }
        openDocumentPresenter = presenter
        presenter.register()
    }

    private func stopOpenDocumentPresentation() {
        openDocumentPresenter?.unregister()
        openDocumentPresenter = nil
    }

    /// Chains events in presenter order. Async reads and conflict copies therefore
    /// cannot overtake a preceding move or deletion notification.
    private func enqueueDocumentEvent(_ event: OpenDocumentEvent) {
        let precedingTask = documentEventTask
        documentEventTask = Task { @MainActor in
            await precedingTask?.value
            guard !Task.isCancelled else { return }
            await handleDocumentEvent(event)
        }
    }

    private func handleDocumentEvent(_ event: OpenDocumentEvent) async {
        switch event {
        case .moved(let oldURL, let newURL):
            guard node.url == oldURL else { return }
            draft.move(to: newURL)
            documentLibrary.publishExternalRevision()
            showSyncNotice(LocalizationController.string("This document was moved on another device."))

        case .changed(let url):
            guard node.url == url, draft.isLoaded else { return }
            do {
                let remoteText = try await documentLibrary.readText(at: url)
                switch draft.decision(forRemoteText: remoteText) {
                case .ignore:
                    break
                case .markSaved:
                    draft.markSaved(remoteText, at: url)
                case .reload:
                    draft.reloadCleanText(remoteText, at: url)
                    showSyncNotice(LocalizationController.string("This document was updated from iCloud."))
                case .preserveRemoteAndSaveDraft:
                    let draftText = draft.text
                    let preserved = try await documentLibrary.preserveRemoteTextAndSaveDraft(
                        remoteText,
                        draftText: draftText,
                        at: url
                    )
                    draft.markSaved(draftText, at: url)
                    if preserved != nil {
                        showSyncNotice(LocalizationController.string("A remote version was preserved as a conflict copy."))
                    }
                }
            } catch {
                showSyncNotice(LocalizationController.string("An iCloud document change could not be applied."))
            }

        case .versionConflict(let url):
            guard node.url == url else { return }
            do {
                let report = try await documentLibrary.resolveVersionConflicts(at: url)
                if !report.materializedURLs.isEmpty {
                    showSyncNotice(LocalizationController.string("Conflicting versions were preserved as separate documents."))
                }
            } catch {
                showSyncNotice(LocalizationController.string("An iCloud document conflict could not be resolved."))
            }

        case .deleted(let url):
            guard node.url == url else { return }
            isBackingFileDeleted = true
            stopOpenDocumentPresentation()
            if draft.isDirty {
                do {
                    _ = try await documentLibrary.recoverDeletedDraft(draft.text, formerlyAt: url)
                    deletionAlert = DocumentDeletionAlert(
                        message: LocalizationController.string("Your unsaved draft was recovered as a new document. Close this deleted document to continue."),
                        retryURL: nil
                    )
                } catch {
                    deletionAlert = DocumentDeletionAlert(
                        message: LocalizationController.string("The deleted document could not be recovered. Keep this screen open and retry after iCloud becomes available."),
                        retryURL: url
                    )
                }
            } else {
                deletionAlert = DocumentDeletionAlert(
                    message: LocalizationController.string("The document was deleted on another device. Close it to return to the library."),
                    retryURL: nil
                )
            }
        }
    }

    private func showSyncNotice(_ message: String) {
        syncNoticeTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) { syncNotice = message }
        syncNoticeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) { syncNotice = nil }
        }
    }

    /// 原地切换到另一篇文档：先保存当前脏内容（用旧 node.url），再换 node 并载入新文本。
    /// 不改导航栈，保持当前预览/编辑模式，标题随 node 自动更新。
    private func switchTo(_ newNode: DocumentNode) {
        guard newNode.url != node.url else { return }
        Haptics.soft()                            // 切换成功给一下细微反馈
        let oldURL = node.url
        let oldText = draft.text
        let shouldSave = draft.isDirty
        Task {
            if shouldSave {
                try? await documentLibrary.writeText(oldText, to: oldURL)
            }
            guard let newText = try? await documentLibrary.readText(at: newNode.url), node.url == oldURL else {
                return
            }
            draft.replaceDocument(with: newNode, text: newText)
            configureOpenDocumentPresentation()
        }
    }
}
