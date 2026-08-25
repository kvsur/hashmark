//
//  AIActionPopover.swift
//  MarkdownApp
//
//  AI 辅助的动作选择弹层：常规文档处理保持克制，自由创作作为开放式入口单独强调。
//  抽成独立视图便于复用，并让调用方用 .popover 锚定到具体按钮——避免 confirmationDialog
//  在 iOS 26 下没有锚点、飘到屏幕顶部的问题（应贴着触发它的 AI 按钮出现）。
//

import SwiftUI

struct AIActionPopover: View {
    /// 选中某个动作时回调；关闭弹层与后续流程由调用方处理。
    let onSelect: (AIAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            VStack(spacing: 2) {
                ForEach(documentActions) { action in
                    actionButton(action)
                }
            }
            .padding(8)

            Divider()
                .padding(.horizontal, Theme.spacing)

            actionButton(.custom, isProminent: true)
                .padding(10)
        }
        // 说明文字需要稳定的横向空间；仍比系统 sheet 紧凑，并可安全容纳在小屏设备内。
        .frame(width: 310)
    }

    private var documentActions: [AIAction] {
        [.continueWriting, .polish, .format]
    }

    private var header: some View {
        HStack(spacing: Theme.spacing) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.aiGradient)
                Image(systemName: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text("AI Assist")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Choose how AI should help with this document")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.spacing)
    }

    private func actionButton(_ action: AIAction, isProminent: Bool = false) -> some View {
        Button {
            onSelect(action)
        } label: {
            HStack(spacing: Theme.spacing) {
                actionIcon(action, isProminent: isProminent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(action.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(action.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isProminent {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.aiGradient)
                        .opacity(0.12)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(AIActionRowButtonStyle())
    }

    @ViewBuilder
    private func actionIcon(_ action: AIAction, isProminent: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isProminent ? AnyShapeStyle(Theme.aiGradient) : AnyShapeStyle(Color(.secondarySystemFill)))

            Image(systemName: action.systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isProminent ? AnyShapeStyle(.white) : AnyShapeStyle(Theme.aiGradient))
        }
        .frame(width: 34, height: 34)
    }
}

private struct AIActionRowButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.68 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
