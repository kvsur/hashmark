//
//  AIWritingPromptView.swift
//  MarkdownApp
//
//  AI 写作会话的输入阶段。上方上下文独立滚动；输入框、附件入口与主行动组成
//  固定在安全区底部的输入坞，半屏内容再长也不会被导航栏、键盘或按钮裁切。
//

import SwiftUI

struct AIWritingPromptView: View {
    let action: AIAction
    let context: String?
    let contextPreview: String?
    @Binding var prompt: String
    @Binding var attachments: [AIAttachment]
    let store: FileStore
    let supportsImages: Bool
    let onNeedsConfig: () -> Void
    let onStart: () -> Void
    let onPromptFocusChange: (Bool) -> Void

    @FocusState private var promptFocused: Bool

    private var disabledReason: LocalizedStringKey? {
        action.validationError(context: context, prompt: prompt)
    }

    private var canStart: Bool {
        let hasPrompt = !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return disabledReason == nil && (action != .custom || hasPrompt)
    }

    var body: some View {
        Group {
            if let preview = contextPreview?.trimmingCharacters(in: .whitespacesAndNewlines),
               !preview.isEmpty {
                selectedContentCard(preview)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composer
        }
        .onChange(of: promptFocused) { _, focused in
            onPromptFocusChange(focused)
        }
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Instructions")
                .font(.subheadline.weight(.semibold))

            TextField(promptPlaceholder, text: $prompt, axis: .vertical)
                .lineLimit(3...8)
                .font(.body)
                .focused($promptFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(minHeight: action == .custom ? 128 : 108, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(.separator), lineWidth: 0.5)
                )
                .accessibilityLabel("Instructions")
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 14) {
            promptSection

            if action.allowsAttachments {
                AIAttachmentBar(
                    attachments: $attachments,
                    store: store,
                    supportsImages: supportsImages,
                    onNeedsConfig: onNeedsConfig
                )
            }

            if let disabledReason {
                Label(disabledReason, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            AIPrimaryButton(title: "Start Generating", isEnabled: canStart, action: onStart)
        }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
    }

    private func selectedContentCard(_ preview: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Selected text", systemImage: "text.quote")
                .font(.subheadline.weight(.semibold))

            // safeAreaInset 已从可用高度中扣除底部输入坞；预览直接吃满全部剩余空间，
            // 长内容交给内部 WKWebView 滚动，不再用固定高度截断。
            MarkdownPreviewView(markdown: preview)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .frame(maxWidth: 620, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var promptPlaceholder: LocalizedStringKey {
        action == .custom ? "Describe the result you want." : "Extra requirements (optional)…"
    }
}
