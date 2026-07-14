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
    let title: String
    /// 接受时回调，交出最终生成文本（首页→新建文档；编辑器→应用到当前文档）。
    let onAccept: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var session: AIWritingSession
    @State private var prompt = ""
    @State private var detent: PresentationDetent = .medium
    @State private var showDiscardConfirm = false

    init(config: AIConfig, action: AIAction, context: String? = nil, title: String, onAccept: @escaping (String) -> Void) {
        self.action = action
        self.context = context
        self.title = title
        self.onAccept = onAccept
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
        .confirmationDialog("放弃本次生成？", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
            Button("放弃", role: .destructive) { session.cancel(); dismiss() }
            Button("继续", role: .cancel) {}
        }
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

            if let disabledReason {
                Text(disabledReason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            AIGradientButton(title: "开始生成", isEnabled: disabledReason == nil, action: start)
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
            Text("正在生成…")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("生成失败", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            // 用现有历史重跑，不重置会话（保住反问/精修上下文）。
            Button("重试") { session.retry() }
        }
    }

    /// 流式中断提示条：说明原因，并提供「重试」重新生成（覆盖已有内容）。
    private func interruptedBanner(_ reason: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("生成已中断")
                    .font(.subheadline.weight(.semibold))
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            // 已保留的部分内容已入历史，「重试」= 丢弃它并重新生成本轮。
            Button("重试") { session.regenerate() }
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
            Button("关闭") { Haptics.light(); attemptClose() }
        }
        ToolbarItem(placement: .confirmationAction) {
            if session.isStreaming {
                Button("停止") { session.stop() }
            } else if session.isDone {
                Button("接受") {
                    onAccept(session.finalText)
                    dismiss()
                }
                .bold()
            }
        }
    }

    // MARK: - 逻辑

    private var promptPlaceholder: String {
        action == .custom ? "比如：帮我写一篇关于……的文章" : "补充要求（可选）…"
    }

    private func start() {
        session.start(messages: action.messages(context: context, prompt: prompt))
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
