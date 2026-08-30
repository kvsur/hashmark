//
//  AIReasoningTraceView.swift
//  MarkdownApp
//
//  推理摘要的独立原生呈现：左侧轨迹线是唯一视觉签名；无卡片、无聊天气泡。
//  组件只处理展示、滚动与 disclosure，阶段判断和正文隔离由 AIWritingSession 负责。
//

import SwiftUI

struct AIReasoningTraceView: View {
    enum State: Equatable {
        case preparing
        case reasoning
        case complete
    }

    let text: String
    let state: State
    @Binding var isExpanded: Bool
    let onDisclosureChange: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var expandedHeight: CGFloat = 220
    @ScaledMetric(relativeTo: .body) private var estimatedLineHeight: CGFloat = 25

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            trace
            VStack(alignment: .leading, spacing: 8) {
                header
                if state != .preparing, isExpanded, !text.isEmpty {
                    reasoningBody
                        .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .accessibilityElement(children: .contain)
    }

    private var trace: some View {
        ZStack(alignment: state == .complete ? .bottom : .top) {
            Capsule()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 2, height: traceHeight)
            Circle()
                .fill(state == .complete ? Color.secondary : Theme.aiAccent)
                .frame(width: 8, height: 8)
                .overlay {
                    if state != .complete {
                        Circle().stroke(Theme.aiAccent.opacity(0.22), lineWidth: 4)
                    }
                }
        }
        .frame(width: 12, alignment: .center)
        .padding(.top, 7)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var header: some View {
        if state == .preparing {
            HStack(spacing: 8) {
                Image(systemName: "pencil.line")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.aiAccent)
                    .accessibilityHidden(true)
                Text("Preparing draft…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 28)
            .accessibilityLabel("Preparing draft…")
        } else {
            Button {
                onDisclosureChange()
                if reduceMotion {
                    isExpanded.toggle()
                } else {
                    withAnimation(.snappy(duration: 0.24)) { isExpanded.toggle() }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(state == .reasoning ? "Reasoning" : "Reasoning Summary")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    if state == .reasoning {
                        Image(systemName: "ellipsis")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.aiAccent)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Hide reasoning" : "Show reasoning")
            .accessibilityValue(state == .reasoning ? "Reasoning in progress" : "Reasoning complete")
        }
    }

    private var reasoningBody: some View {
        BottomFollowingScrollView(updateToken: text) {
            Text(text)
                .font(.system(.body, design: .serif))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.updatesFrequently)
        }
        .scrollIndicators(.visible)
        .frame(height: reasoningViewportHeight)
    }

    /// ScrollView 没有内在高度；显式给出随内容增长的视口，避免在 HStack 中被压成 0。
    /// 长内容到达上限后由内部滚动承接，Dynamic Type 通过 ScaledMetric 同步放大上限。
    private var reasoningViewportHeight: CGFloat {
        let estimatedLines = max(2, Int(ceil(Double(text.count) / 24.0)))
        return min(expandedHeight, CGFloat(estimatedLines) * estimatedLineHeight + 14)
    }

    private var traceHeight: CGFloat {
        if state == .preparing || !isExpanded { return 28 }
        return min(expandedHeight, 92)
    }
}
