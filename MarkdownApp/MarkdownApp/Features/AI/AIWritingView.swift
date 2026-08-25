//
//  AIWritingView.swift
//  MarkdownApp
//
//  AI 写作会话的核心 UI（通用）：首页「生成整篇」与编辑器内「续写/润色/整理/自定义」都用它。
//  交互：prompt 半屏输入 → 返回后转全屏流式预览 → 诉求含糊时模型反问、弹答题卡片 → 生成完成后
//  底部保留精修坞可继续调整/重新生成 → 接受（回调应用）/ 放弃（二次确认）。
//  用 AIWritingSession 驱动多轮状态，用 AIStreamingPreview 边收边渲染，用 AIClarifyCard 答题。
//

import SwiftUI

struct AIWritingView: View {
    let action: AIAction
    /// 文档上下文；首页生成整篇为 nil。
    let context: String?
    /// 需要在填 prompt 阶段「展示给用户看」的上下文预览（如选区润色时的选中内容）。
    /// 仅用于可视化，不参与请求组装（请求上下文仍走 context）；整篇动作传 nil 不展示。
    let contextPreview: String?
    let title: LocalizedStringKey
    /// 接受时回调，交出最终生成文本（首页→新建文档；编辑器→应用到当前文档）。
    let onAccept: (String) -> Void
    /// 输入阶段按内容复杂度选择的紧凑高度；生成后统一转为全屏。
    private let idleDetent: PresentationDetent

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var session: AIWritingSession
    @State private var prompt = ""
    @State private var attachments: [AIAttachment] = []
    /// 流式预览：用户是否贴底跟随最新（false = 已上滑离底，显示「跳到最新」浮标）。
    @State private var streamingScroll = AIStreamingScrollState()
    /// 自增以命令流式预览「跳到最新」。
    @State private var scrollToLatestToken = 0
    /// reasoning 默认在生成时展开，正文到达后自动收拢；用户一旦手动操作，本轮不再抢状态。
    @State private var reasoningDisclosure = AIReasoningDisclosureState()
    @State private var detent: PresentationDetent
    @State private var showDiscardConfirm = false
    /// 当前 AI 配置的本地副本：用于读取 Registry 解析出的附件能力。
    @State private var config: AIConfig
    @State private var showConfigEditor = false

    /// 引用库内文档用；FileStore 无状态（直接读 Documents），就地创建即可。
    private let store = FileStore()
    private let aiConfigStore = AIConfigStore()

    init(config: AIConfig, action: AIAction, context: String? = nil, contextPreview: String? = nil, title: LocalizedStringKey, onAccept: @escaping (String) -> Void) {
        self.action = action
        self.context = context
        self.contextPreview = contextPreview
        self.title = title
        self.onAccept = onAccept
        let initialDetent = Self.preferredIdleDetent(action: action, contextPreview: contextPreview)
        self.idleDetent = initialDetent
        _detent = State(initialValue: initialDetent)
        _config = State(initialValue: config)
        _session = State(
            initialValue: AIWritingSession(
                config: config,
                tools: Self.sessionTools(for: action)
            )
        )
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                // 有内容时禁止下滑直接关，逼走「放弃」二次确认，避免误丢。
                .interactiveDismissDisabled(session.hasContent || session.isStreaming)
        }
        .presentationDetents([idleDetent, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        .onAppear { expandForConstrainedHeightIfNeeded() }
        .onChange(of: dynamicTypeSize) { _, _ in expandForConstrainedHeightIfNeeded() }
        .onChange(of: verticalSizeClass) { _, _ in expandForConstrainedHeightIfNeeded() }
        // 一旦离开填 prompt 阶段（流式/反问/完成）就转全屏，给内容与答题足够空间。
        // 同时在「开始产出正文」与「本轮结束」各给一次触觉反馈（精修/重新生成会再次经历这两态）。
        .onChange(of: session.phase) { oldPhase, phase in
            if phase != .idle { detent = .large }
            if oldPhase == .loading && (phase == .reasoning || phase == .streaming) {
                Haptics.soft()                 // 开始生成
                streamingScroll.beginTurn()    // 新一轮回到贴底跟随，不沿用上一轮的上滑态
            }
            if oldPhase != .done, phase == .done { Haptics.success() }            // 结束生成
        }
        .onChange(of: session.presentationState.hasStartedAnswer) { _, started in
            if started { reasoningDisclosure.answerStarted() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background { session.interruptForBackground() }
        }
        .confirmationDialog("Discard this generation?", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { session.cancel(); dismiss() }
            Button("Keep Going", role: .cancel) {}
        }
        // 当前 Provider/模型未确认图片能力时，入口可引导到配置页；关闭后重载能力状态。
        .sheet(isPresented: $showConfigEditor, onDismiss: reloadConfig) {
            AIConfigEditorView(store: aiConfigStore)
        }
        .rebuildsOnLanguageChange()
    }

    // MARK: - 各阶段内容

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .idle:
            AIWritingPromptView(
                action: action,
                context: context,
                contextPreview: contextPreview,
                prompt: $prompt,
                attachments: $attachments,
                store: store,
                supportsImages: config.effectiveCapabilities?.imageInput.isEnabled == true,
                onNeedsConfig: { showConfigEditor = true },
                onStart: start,
                onPromptFocusChange: { focused in
                    // 键盘会明显压缩半屏可用高度；先转全屏，再让系统完成键盘动画。
                    if focused { detent = .large }
                }
            )
        case .loading, .reasoning:
            generationArea
        case .awaitingAnswer(let request):
            // 反问：渲染答题卡片替代正文区，工具内容绝不进正文。
            AIClarifyCard(request: request) { answer in
                session.answer(answer)
            }
        case .streaming, .done, .cancelled, .interrupted:
            generationArea
        case .error(let message):
            errorView(message)
        }
    }

    /// 生成区：准备/推理轨迹 + 正文预览 +（完成后）底部精修坞。
    private var generationArea: some View {
        AIWritingGenerationView(
            session: session,
            streamingScroll: $streamingScroll,
            scrollToLatestToken: $scrollToLatestToken,
            reasoningDisclosure: $reasoningDisclosure
        )
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Generation Failed", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            // 用现有历史重跑，不重置会话（保住反问/精修上下文）。
            Button("Retry") { session.retry() }
        }
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                Haptics.light()
                attemptClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
            }
            .accessibilityLabel("Close")
        }
        ToolbarItem(placement: .confirmationAction) {
            if session.isStreaming {
                Button("Stop") { session.stop() }
            } else if session.canAccept {
                Button("Accept") {
                    onAccept(session.finalText)
                    dismiss()
                }
                .bold()
            }
        }
    }

    // MARK: - 逻辑

    private static func preferredIdleDetent(
        action: AIAction,
        contextPreview: String?
    ) -> PresentationDetent {
        if let contextPreview, !contextPreview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .fraction(0.70)
        }
        return action.allowsAttachments ? .fraction(0.62) : .fraction(0.42)
    }

    /// 仅 custom 动作允许模型反问澄清；其它动作不带工具。
    private static func sessionTools(for action: AIAction) -> [AITool] {
        action.allowsClarify ? [ClarifyTool.definition] : []
    }

    /// 横屏或无障碍字号下，底部输入坞需要更多垂直空间，直接使用全屏高度避免控件互相遮挡。
    private func expandForConstrainedHeightIfNeeded() {
        guard session.phase == .idle else { return }
        if verticalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize {
            detent = .large
        }
    }

    private func start() {
        // 配置页可以覆盖在当前写作页上。提交前必须重新读取持久化配置并创建会话，
        // 否则搜索开关虽然已经显示为开启，请求仍会沿用打开页面时的旧快照。
        let latestConfig = aiConfigStore.load()
        config = latestConfig
        session = AIWritingSession(
            config: latestConfig,
            tools: Self.sessionTools(for: action)
        )

        // 附件（图片+引用文档）随首轮消息带下去：图片走多模态块、文档引用注入 user 文本。
        // 精修/重新生成不重复带图——refine 走 refineMessages（无附件），regenerate 复用已含图的首条消息。
        reasoningDisclosure.beginTurn()
        streamingScroll.beginTurn()
        session.start(
            messages: action.messages(context: context, prompt: prompt, attachments: attachments),
            attachments: attachments
        )
    }

    private func reloadConfig() {
        let latestConfig = aiConfigStore.load()
        config = latestConfig
        guard session.phase == .idle else { return }
        session = AIWritingSession(
            config: latestConfig,
            tools: Self.sessionTools(for: action)
        )
    }

    /// 关闭：有已生成内容则二次确认，否则直接关。
    private func attemptClose() {
        if session.hasContent {
            showDiscardConfirm = true
        } else {
            session.cancel()
            dismiss()
        }
    }
}
