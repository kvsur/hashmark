//
//  LanguagePickerSheet.swift
//  MarkdownApp
//
//  语言切换：跟随系统 + 7 种显式语言，当前项打勾。选中即写入偏好、界面立刻换语言（免重启）。
//  视图只负责「怎么显示」，语言的解析与生效在 LocalizationController，偏好持久化在 SettingsStore。
//

import SwiftUI

struct LanguagePickerSheet: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(LanguagePreference.allCases) { preference in
                        row(for: preference)
                    }
                } footer: {
                    Text("The app follows your device language when set to Follow System. Unsupported languages fall back to English.")
                }
            }
            .navigationTitle("Language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .rebuildsOnLanguageChange()
    }

    private func row(for preference: LanguagePreference) -> some View {
        Button {
            guard preference != settings.language else { return }
            Haptics.light()
            settings.language = preference
        } label: {
            HStack {
                name(for: preference)
                Spacer()
                if preference == settings.language {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
        }
        .tint(.primary)
    }

    /// 「跟随系统」是界面文案、要跟着当前语言走；具体语言用母语自称、恒定不变
    /// （用户看不懂当前界面语言时才来这里，见 LanguagePreference.nativeName 的说明）。
    @ViewBuilder
    private func name(for preference: LanguagePreference) -> some View {
        if let native = preference.nativeName {
            Text(verbatim: native)
        } else {
            Text("Follow System")
        }
    }
}
