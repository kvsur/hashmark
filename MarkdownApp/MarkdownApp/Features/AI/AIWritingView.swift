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
    let title: LocalizedStringKey
    /// 接受时回调，交出最终生成文本（首页→新建文档；编辑器→应用到当前文档）。
    let onAccept: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var session: AIWritingSession
    @State private var prompt = ""
    @State private var attachments: [AIAttachment] = []
    @State private var detent: PresentationDetent = .medium
    @State private var showDiscardConfirm = false
    /// 当前 AI 配置的本地副本：用于读取 supportsImages 门控图片入口。
    /// 用户在附件条点图片按钮进配置页开启后，回来重载它以刷新门控。
    @State private var config: AIConfig
    @State private var showConfigEditor = false

    /// 引用库内文档用；FileStore 无状态（直接读 Documents），就地创建即可。
    private let store = FileStore()
    private let aiConfigStore = AIConfigStore()

    init(config: AIConfig, action: AIAction, context: String? = nil, title: LocalizedStringKey, onAccept: @escaping (String) -> Void) {
        self.action = action
        self.context = context
        self.title = title
        self.onAccept = onAccept
        _config = State(initialValue: config)
        // 仅 custom 动作允许模型反问澄清；其它动作不带工具。
        let tools = action.allowsClarify ? [ClarifyTool.definition] : []
        _session = State(initialValue: AIWritingSession(config: config, tools: tools))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                // 有内容时禁止下滑直接关，逼走「放弃」二次确认，避免误丢。
                .interactiveDismissDisabled(session.hasContent)
        }
        .presentationDetents([.medium, .large], selection: $detent)
        // 一旦离开填 prompt 阶段（流式/反问/完成）就转全屏，给内容与答题足够空间。
        // 同时在「开始产出正文」与「本轮结束」各给一次触觉反馈（精修/重新生成会再次经历这两态）。
        .onChange(of: session.phase) { oldPhase, phase in
            if phase != .idle { detent = .large }
            if oldPhase != .streaming, phase == .streaming { Haptics.soft() }     // 开始生成
            if oldPhase != .done, phase == .done { Haptics.success() }            // 结束生成
        }
        .confirmationDialog("Discard this generation?", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { session.cancel(); dismiss() }
            Button("Keep Going", role: .cancel) {}
        }
        // 未开启「支持图片」时点图片按钮跳到此配置页；关闭后重载配置，刷新图片入口门控。
        // 会话仍用初始 config（只切图片能力、不改端点，无需重建会话）。
        .sheet(isPresented: $showConfigEditor, onDismiss: { config = aiConfigStore.load() }) {
            AIConfigEditorView(store: aiConfigStore)
        }
        .rebuildsOnLanguageChange()
    }

    // MARK: - 各阶段内容

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .idle:
            promptInput
        case .loading:
            loadingView
        case .awaitingAnswer(let request):
            // 反问：渲染答题卡片替代正文区，工具内容绝不进正文。
            AIClarifyCard(request: request) { answer in
                session.answer(answer)
            }
        case .streaming, .done:
            streamingArea
        case .error(let message):
            errorView(message)
        }
    }

    /// 流式/完成区：正文预览 +（完成后）底部精修坞。
    private var streamingArea: some View {
        VStack(spacing: 0) {
            // 流式途中断网等中断：保留已生成内容，顶部提示可接受部分或重试。
            if let reason = session.interruptedReason {
                interruptedBanner(reason)
            }
            // 流式中显示本轮实时缓冲；完成/中断态显示已确认全文，避免空缓冲盖掉已有内容。
            AIStreamingPreview(markdown: session.isStreaming ? session.text : session.finalText,
                               isFinal: session.isDone, colorScheme: colorScheme)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // 生成完成后保留输入与按钮，可继续调整或重新生成。
            if session.isDone {
                AIRefineBar(
                    onRefine: { session.refine($0) },
                    onRegenerate: { session.regenerate() }
                )
            }
        }
    }

    private var promptInput: some View {
        // 导航栏标题已展示 action.label，此处不再重复标题，直接给输入区。
        let disabledReason = action.validationError(context: context, prompt: prompt)
        // custom 仍需填文字才能发起（附件只是补充上下文、不能替代指令）；只是不再显示专门的
        // 错误文案，按钮静默禁用即可。其它动作沿用 disabledReason（如续写需非空文档上下文）。
        let hasPrompt = !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let canStart = disabledReason == nil && (action != .custom || hasPrompt)
        return VStack(alignment: .leading, spacing: 16) {
            // 自绘填充+描边的输入框：比 .roundedBorder 在深浅色下都与 sheet 背景明显区分。
            TextField(promptPlaceholder, text: $prompt, axis: .vertical)
                .lineLimit(4...10)
                .font(.body)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(.separator), lineWidth: 1)
                )

            // 附件条仅生成类动作（续写/自由创作）可用；填 prompt 阶段可编辑。
            if action.allowsAttachments {
                AIAttachmentBar(
                    attachments: $attachments,
                    store: store,
                    supportsImages: config.supportsImages,
                    onNeedsConfig: { showConfigEditor = true }
                )
            }

            if let disabledReason {
                Text(disabledReason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            AIGradientButton(title: "Start Generating", isEnabled: canStart, action: start)
                .frame(maxWidth: .infinity)  // 让胶囊按钮在整行内居中

            Spacer(minLength: 0)
        }
        .padding(20)
    }

    /// 等待首个返回时的品牌化占位：渐变 sparkles + 呼吸动效，比裸 ProgressView 更贴合 AI 语境。
    private var loadingView: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(Theme.aiGradient)
                .symbolEffect(.pulse, options: .repeating)
            Text("Generating…")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    /// 流式中断提示条：说明原因，并提供「重试」重新生成（覆盖已有内容）。
    private func interruptedBanner(_ reason: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Generation Interrupted")
                    .font(.subheadline.weight(.semibold))
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            // 已保留的部分内容已入历史，「重试」= 丢弃它并重新生成本轮。
            Button("Retry") { session.regenerate() }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.orange.opacity(0.12))
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close") { Haptics.light(); attemptClose() }
        }
        ToolbarItem(placement: .confirmationAction) {
            if session.isStreaming {
                Button("Stop") { session.stop() }
            } else if session.isDone {
                Button("Accept") {
                    onAccept(session.finalText)
                    dismiss()
                }
                .bold()
            }
        }
    }

    // MARK: - 逻辑

    private var promptPlaceholder: LocalizedStringKey {
        action == .custom ? "Describe what you want to create — a plan, a proposal, marketing copy, a recipe, anything." : "Extra requirements (optional)…"
    }

    private func start() {
        // 附件（图片+引用文档）随首轮消息带下去：图片走多模态块、文档引用注入 user 文本。
        // 精修/重新生成不重复带图——refine 走 refineMessages（无附件），regenerate 复用已含图的首条消息。
        session.start(messages: action.messages(context: context, prompt: prompt, attachments: attachments))
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
