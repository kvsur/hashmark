//
//  AIClarifyCard.swift
//  MarkdownApp
//
//  反问澄清答题卡片：把模型的 ClarifyRequest 可视化成可交互的答题界面，
//  供用户以 单选/多选/文字 作答；答完回调 onSubmit(答案文本)，由会话层回填给模型继续生成。
//  设计以小屏可操作性为先：问题醒目、留白充足、选项为舒适高度的圆角行、推荐项以品牌胶囊标注，
//  主行动用居中胶囊按钮（不做长扁按钮）。
//

import SwiftUI

struct AIClarifyCard: View {
    let request: ClarifyRequest
    /// 提交答案（选择型为选中项文案，多选以「、」连接；文字型为输入内容）。
    let onSubmit: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                answerControl
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Just checking one thing", systemImage: "questionmark.bubble")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.aiGradient)
            // 问题醒目、可换行、行距舒展，不贴边。
            Text(request.question)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var answerControl: some View {
        switch request.answerSpec {
        case .singleSelect(let options):
            // 单选：点选即提交，最快。
            VStack(spacing: 12) {
                ForEach(options) { option in
                    OptionRow(label: option.label, recommended: option.recommended, selected: false) {
                        onSubmit(option.label)
                    }
                }
            }
        case .multiSelect(let options):
            MultiSelectAnswer(options: options, onSubmit: onSubmit)
        case .text:
            TextAnswer(onSubmit: onSubmit)
        }
    }
}

// MARK: - 选项行（单选/多选共用）

private struct OptionRow: View {
    let label: String
    let recommended: Bool
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.secondary))
                Text(label)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if recommended { RecommendedBadge() }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color(.separator),
                                  lineWidth: selected ? 2 : 1)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private struct RecommendedBadge: View {
    var body: some View {
        Text("Recommended")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.aiGradient, in: Capsule())
    }
}

// MARK: - 多选

private struct MultiSelectAnswer: View {
    let options: [ClarifyRequest.Option]
    let onSubmit: (String) -> Void
    @State private var selected: Set<String> = []

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                ForEach(options) { option in
                    OptionRow(label: option.label, recommended: option.recommended,
                              selected: selected.contains(option.label)) {
                        toggle(option.label)
                    }
                }
            }
            AIGradientButton(title: selected.isEmpty ? "Confirm" : "Confirm (\(selected.count))",
                             systemImage: "checkmark",
                             isEnabled: !selected.isEmpty) {
                // 按选项原顺序拼接，读起来自然。这段答案会发给模型，
                // 故用当前界面语言的列表格式（中/日为「、」，德/俄为「, … und/и …」），
                // 不写死顿号。
                let answer = options.map(\.label).filter(selected.contains)
                    .formatted(.list(type: .and).locale(LocalizationController.current))
                onSubmit(answer)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func toggle(_ label: String) {
        if selected.contains(label) { selected.remove(label) } else { selected.insert(label) }
    }
}

// MARK: - 文字

private struct TextAnswer: View {
    let onSubmit: (String) -> Void
    @State private var text = ""

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 20) {
            TextField("Type your answer here…", text: $text, axis: .vertical)
                .lineLimit(3...8)
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
            AIGradientButton(title: "Submit", systemImage: "paperplane.fill",
                             isEnabled: !trimmed.isEmpty) {
                onSubmit(trimmed)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
