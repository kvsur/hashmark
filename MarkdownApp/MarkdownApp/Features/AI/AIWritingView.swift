//
//  AIWritingView.swift
//  MarkdownApp
//
//  AI 写作会话的核心 UI（通用）：首页「生成整篇」与编辑器内「续写/润色/整理/自定义」都用它。
//  交互：prompt 半屏输入 → 开始返回立即转全屏流式预览 → 接受（回调应用）/ 放弃（二次确认）。
//  用 AIWritingSession 驱动状态，用 AIStreamingPreview 边收边渲染。
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
        _session = State(initialValue: AIWritingSession(config: config))
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
        // 一开始返回（进入 streaming）立即转全屏；完成也保持全屏。
        .onChange(of: session.phase) { _, phase in
            if phase == .streaming || phase == .done { detent = .large }
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
            statusView("正在生成…", systemImage: "sparkles", showsProgress: true)
        case .streaming, .done:
            AIStreamingPreview(markdown: session.text, isFinal: session.isDone, colorScheme: colorScheme)
                .ignoresSafeArea(edges: .bottom)
        case .error(let message):
            ContentUnavailableView {
                Label("生成失败", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("重试") { start() }
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

            // 品牌渐变胶囊按钮：居中、不铺满整行，加高触感更好；禁用时去色+降透明清晰可辨。
            Button(action: start) {
                Label("开始生成", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(minWidth: 180)
                    .padding(.vertical, 15)
                    .padding(.horizontal, 40)
                    .background(Theme.aiGradient, in: Capsule())
            }
            .buttonStyle(.plain)
            .grayscale(disabledReason != nil ? 1 : 0)
            .opacity(disabledReason != nil ? 0.5 : 1)
            .disabled(disabledReason != nil)
            .frame(maxWidth: .infinity)  // 让胶囊按钮在整行内居中

            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private func statusView(_ text: String, systemImage: String, showsProgress: Bool) -> some View {
        VStack(spacing: 12) {
            if showsProgress { ProgressView() }
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("关闭") { attemptClose() }
        }
        ToolbarItem(placement: .confirmationAction) {
            if session.isStreaming {
                Button("停止") { session.stop() }
            } else if session.isDone {
                Button("接受") {
                    onAccept(session.text)
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
