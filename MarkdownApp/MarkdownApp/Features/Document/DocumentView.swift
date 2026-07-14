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
    let store: FileStore
    /// 当前文档节点。设为可变状态，配合快速切换器实现原地换文档（不改导航栈）。
    @State private var node: DocumentNode

    init(store: FileStore, node: DocumentNode) {
        self.store = store
        _node = State(initialValue: node)
    }

    /// 两种模式：预览（渲染）/ 编辑（源码）。
    enum Mode: String, CaseIterable, Identifiable {
        case preview, edit
        var id: String { rawValue }
        var label: String { self == .preview ? "预览" : "编辑" }
    }

    @State private var text: String = ""
    /// 上次已写入磁盘的内容，用来判断是否有未保存改动（脏检查）。
    @State private var savedText: String = ""
    @State private var mode: Mode = .preview
    @State private var loaded = false
    @State private var showSwitcher = false
    /// 桥接预览 WebView，供预览态「分享 - 长截图」取用。
    @State private var previewHandle = PreviewHandle()

    // AI 写作：点按钮先选动作，过配置门槛后弹会话，接受则应用回文档。
    private let aiConfigStore = AIConfigStore()
    @State private var showAIActions = false
    @State private var aiTrigger = false
    @State private var pendingAction: AIAction?
    @State private var aiLaunch: AILaunch?

    var body: some View {
        content
            // 预览左滑 → 编辑；编辑右滑 → 预览。方向判定与滚动/选择冲突收敛在封装里。
            .horizontalSwitch(
                onSwipeLeft: { if mode == .preview { switchMode(to: .edit) } },
                onSwipeRight: { if mode == .edit { switchMode(to: .preview) } }
            )
            .navigationTitle(node.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    // 走 switchMode 让「点分段控件」与「滑动切换」共用同一套过渡动画。
                    Picker("模式", selection: Binding(get: { mode }, set: { switchMode(to: $0) })) {
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
                // 底部两个按钮一左一右：中间放弹性空隙把「切换文档」推到左下角、AI 推到右下角。
                // 各自成一枚独立玻璃胶囊（iOS 18 无 ToolbarSpacer 时用 Group + Spacer 回退）。
                if #available(iOS 26, *) {
                    ToolbarItem(placement: .bottomBar) { switchDocButton }
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) { aiActionButton }
                } else {
                    ToolbarItemGroup(placement: .bottomBar) {
                        switchDocButton
                        Spacer()
                        aiActionButton
                    }
                }
            }
            .aiConfigGate(trigger: $aiTrigger, store: aiConfigStore) { config in
                if let action = pendingAction {
                    aiLaunch = AILaunch(config: config, action: action)
                }
            }
            .sheet(item: $aiLaunch) { launch in
                AIWritingView(
                    config: launch.config,
                    action: launch.action,
                    context: text,
                    title: launch.action.label
                ) { result in
                    applyAI(launch.action, result)
                }
            }
            .onAppear(perform: loadIfNeeded)
            // 切回预览时先落盘，保证预览读到的是最新且已持久化的内容。
            .onChange(of: mode) { _, newMode in
                if newMode == .preview { save() }
            }
            .onDisappear(perform: save)
            .sheet(isPresented: $showSwitcher) {
                DocumentSwitcherSheet(store: store, currentURL: node.url) { selected in
                    switchTo(selected)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
            Label("切换文档", systemImage: "rectangle.stack")
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
                    pendingAction = action
                    showAIActions = false
                    // 延迟触发，确保 popover 关闭动画完成后再触发 AI 流程，
                    // 避免视图层级变化导致状态更新丢失。
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(100))
                        aiTrigger = true
                    }
                }
                .presentationCompactAdaptation(.popover)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .preview:
            MarkdownPreviewView(markdown: text, handle: previewHandle)
                .ignoresSafeArea(edges: .bottom)
                // 预览在「编辑的左边」：切走时向左滑出、回来时从左侧滑入。
                .transition(.move(edge: .leading))
        case .edit:
            EditorView(text: $text)
                // 编辑在「预览的右边」：切走时向右滑出、进入时从右侧滑入。
                .transition(.move(edge: .trailing))
        }
    }

    /// 带过渡动画地切换预览/编辑；同时驱动 content 的 move 过渡，形成左右分页观感。
    /// 落盘仍由 onChange(of: mode) 负责（切到预览时先保存），这里只管动画与状态。
    private func switchMode(to newMode: Mode) {
        guard mode != newMode else { return }
        Haptics.soft()   // 切换成功给一下细微反馈（点分段控件与滑动切换共用）
        withAnimation(.easeInOut(duration: 0.25)) { mode = newMode }
    }

    // MARK: - AI

    /// 接受 AI 结果：按动作应用到当前文档并落盘。
    /// 续写/自定义=追加文末（不破坏原文）；润色/整理=替换全文。上下文用整篇（暂不支持选中）。
    private func applyAI(_ action: AIAction, _ result: String) {
        switch action.editorApplyMode {
        case .append:
            text = text.isEmpty ? result : text + "\n\n" + result
        case .replace:
            text = result
        }
        save()
    }

    // MARK: - 逻辑

    /// 首次出现时从磁盘读入一次；之后 text 即本屏数据源，不再重复读盘。
    private func loadIfNeeded() {
        guard !loaded else { return }
        text = store.readText(at: node.url)
        savedText = text
        loaded = true
    }

    /// 有改动才写盘，避免无谓 IO 与修改时间抖动。
    private func save() {
        guard loaded, text != savedText else { return }
        try? store.writeText(text, to: node.url)
        savedText = text
    }

    /// 原地切换到另一篇文档：先保存当前脏内容（用旧 node.url），再换 node 并载入新文本。
    /// 不改导航栈，保持当前预览/编辑模式，标题随 node 自动更新。
    private func switchTo(_ newNode: DocumentNode) {
        guard newNode.url != node.url else { return }
        Haptics.soft()                            // 切换成功给一下细微反馈
        save()                                    // 存旧文档
        node = newNode
        text = store.readText(at: newNode.url)    // 载入新文档
        savedText = text
    }
}
