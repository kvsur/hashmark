//
//  SettingsView.swift
//  MarkdownApp
//
//  设置页：主题 / 语言 / AI 接口配置 / 关于。经主页左上角齿轮按钮以 sheet 弹出。
//  本视图只负责「怎么显示」，主题读写走 environment 里的 SettingsStore、
//  AI 配置读写走 AIConfigStore（逻辑外移）。多个二级弹层用 SettingsSheet 枚举统一驱动。
//

import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var sheet: SettingsSheet?
    // AI 配置的本地读写服务；供 AI 配置编辑器载入/保存。
    private let aiConfigStore = AIConfigStore()

    var body: some View {
        // @Bindable 让 @Observable 的属性可直接做 Binding（Picker selection）。
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section("外观") {
                    Picker("主题", selection: $settings.theme) {
                        ForEach(ThemePreference.allCases) { pref in
                            Text(pref.label).tag(pref)
                        }
                    }
                    .tallSegmentedPicker()
                }

                Section("语言") {
                    disclosureRow("切换语言", systemImage: "globe") { sheet = .language }
                }

                Section("AI") {
                    disclosureRow("AI 接口配置", systemImage: "sparkles") { sheet = .aiConfig }
                }

                Section {
                    disclosureRow("关于", systemImage: "info.circle") { sheet = .about }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(item: $sheet, content: sheetContent)
        }
    }

    // MARK: - 二级弹层

    @ViewBuilder
    private func sheetContent(_ sheet: SettingsSheet) -> some View {
        switch sheet {
        case .language: LanguagePlaceholderSheet()
        case .about: AboutView()
        case .aiConfig: AIConfigEditorView(store: aiConfigStore)
        }
    }

    // MARK: - 复用行

    /// 可点的「标题 + 尾部箭头」披露行，语言/AI/关于三处共用（DRY）。
    private func disclosureRow(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .tint(.primary)
    }
}

/// 设置页可能弹出的二级页种类。
enum SettingsSheet: Int, Identifiable {
    case language, about, aiConfig
    var id: Int { rawValue }
}

/// 语言切换占位：功能未上线时给一个清晰、不崩的反馈（沿用 App 内占位弹层风格）。
private struct LanguagePlaceholderSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("多语言", systemImage: "globe")
            } description: {
                Text("语言切换将在后续版本提供。")
            }
            .navigationTitle("切换语言")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
