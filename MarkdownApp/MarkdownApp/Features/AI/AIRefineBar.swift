//
//  AIRefineBar.swift
//  MarkdownApp
//
//  生成完成后的底部精修输入坞：让用户继续把诉求告诉 Agent（如「更精简些」「换个角度」）
//  做二次生成，或一键「重新生成」。小屏优先：胶囊输入 + 圆形发送（不做长扁按钮），
//  次要的「重新生成」用轻量文字按钮。挂在预览底部（safeAreaInset）。
//

import SwiftUI

struct AIRefineBar: View {
    /// 提交精修指令（追加为新一轮用户消息）。
    let onRefine: (String) -> Void
    /// 重新生成上一轮结果。
    let onRegenerate: () -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("继续调整，如：更精简 / 换个角度…", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($focused)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color(.separator), lineWidth: 1)
                    )

                sendButton
            }

            // 次要操作：轻量文字按钮，居中，不与主输入争夺注意力。
            Button(action: onRegenerate) {
                Label("重新生成", systemImage: "arrow.clockwise")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private var sendButton: some View {
        Button {
            let instruction = trimmed
            guard !instruction.isEmpty else { return }
            text = ""
            focused = false
            onRefine(instruction)
        } label: {
            Image(systemName: "arrow.up")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Theme.aiGradient))
        }
        .buttonStyle(.plain)
        .grayscale(trimmed.isEmpty ? 1 : 0)
        .opacity(trimmed.isEmpty ? 0.5 : 1)
        .disabled(trimmed.isEmpty)
    }
}
