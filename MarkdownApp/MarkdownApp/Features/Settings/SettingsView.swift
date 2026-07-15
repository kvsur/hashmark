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
                Section("Appearance") {
                    Picker("Theme", selection: $settings.theme) {
                        ForEach(ThemePreference.allCases) { pref in
                            Text(pref.label).tag(pref)
                        }
                    }
                    .tallSegmentedPicker()
                }

                Section("Language") {
                    disclosureRow("Switch Language", systemImage: "globe") { sheet = .language }
                }

                Section("AI") {
                    disclosureRow("AI Endpoint", systemImage: "sparkles") { sheet = .aiConfig }
                }

                Section {
                    disclosureRow("About", systemImage: "info.circle") { sheet = .about }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $sheet, content: sheetContent)
        }
        .rebuildsOnLanguageChange()
    }

    // MARK: - 二级弹层

    @ViewBuilder
    private func sheetContent(_ sheet: SettingsSheet) -> some View {
        switch sheet {
        case .language: LanguagePickerSheet()
        case .about: AboutView()
        case .aiConfig: AIConfigEditorView(store: aiConfigStore)
        }
    }

    // MARK: - 复用行

    /// 可点的「标题 + 尾部箭头」披露行，语言/AI/关于三处共用（DRY）。
    /// title 取 LocalizedStringKey 而非 String —— String 会被 Label 当作字面量原样显示、绕过本地化。
    private func disclosureRow(
        _ title: LocalizedStringKey,
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
