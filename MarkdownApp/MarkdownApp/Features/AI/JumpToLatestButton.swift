//
//  JumpToLatestButton.swift
//  MarkdownApp
//
//  AI 流式预览里的「跳到最新」浮标：用户上滑离底看上文时出现，点按滚回最新内容。
//  外圈是持续旋转的 AI 品牌渐变环，表示「仍在生成中」；生成结束由上层移除本视图，
//  故这里只管「一直转」，不需要自身停转逻辑。
//

import SwiftUI

struct JumpToLatestButton: View {
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let size: CGFloat = 40
    private let ringWidth: CGFloat = 3
    @State private var spinning = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // 底盘：材质圆，深浅色下都与内容区分明显。
                Circle()
                    .fill(.regularMaterial)
                    .overlay(Circle().strokeBorder(Color(.separator), lineWidth: 0.5))

                // 生成中指示：旋转的品牌渐变环。
                Circle()
                    .strokeBorder(Theme.aiAngularGradient, lineWidth: ringWidth)
                    .rotationEffect(.degrees(spinning && !reduceMotion ? 360 : 0))
                    .animation(
                        reduceMotion ? nil : .linear(duration: 1.1).repeatForever(autoreverses: false),
                        value: spinning
                    )

                Image(systemName: "arrow.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(width: size, height: size)
            // 轻微阴影，强调它悬浮于内容之上。
            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Jump to Latest"))
        .accessibilityHint(Text("Returns to the newest part of the answer and resumes following updates."))
        .onAppear { spinning = true }
    }
}
