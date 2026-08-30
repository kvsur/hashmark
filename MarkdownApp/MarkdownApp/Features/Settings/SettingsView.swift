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
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var documentLibrary: DocumentLibraryController
    @Environment(\.dismiss) private var dismiss
    @State private var sheet: SettingsSheet?
    @State private var iCloudConfirmation: ICloudSwitchConfirmation?
    @State private var requestedStorageMode: DocumentStorageMode?
    // AI 配置的本地读写服务；供 AI 配置编辑器载入/保存。
    private let aiConfigStore = AIConfigStore()

    var body: some View {
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

                Section("Documents") {
                    Toggle("Sync with iCloud", isOn: Binding(
                        get: { documentLibrary.storageMode == .iCloud },
                        set: requestStorageMode
                    ))
                    .disabled(isMigrating)

                    Label(iCloudStatusTitle, systemImage: iCloudStatusSymbol)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text("iCloud Sync"))
                        .accessibilityValue(Text(iCloudStatusTitle))

                    if case .migrating(_, let progress) = documentLibrary.state {
                        ProgressView(value: progress)
                            .accessibilityLabel(Text(iCloudStatusTitle))
                    }
                    if needsICloudAttention {
                        Button("Retry") { retryICloudAction() }
                    }
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
            .alert(item: $iCloudConfirmation, content: iCloudAlert)
        }
        .rebuildsOnLanguageChange()
    }

    private var isMigrating: Bool {
        if case .migrating = documentLibrary.state { return true }
        return false
    }

    private var needsICloudAttention: Bool {
        switch documentLibrary.state {
        case .failed, .cloudUnavailable: return true
        default: return false
        }
    }

    private var iCloudStatusTitle: LocalizedStringKey {
        switch documentLibrary.state {
        case .localReady: return "Stored on This Device"
        case .checkingCloud: return "Checking iCloud…"
        case .cloudReady: return "Synced with iCloud"
        case .syncing: return "Syncing with iCloud…"
        case .migrating(let direction, _):
            return direction == .enableICloud
                ? "Moving Documents to iCloud…"
                : "Saving Documents on This Device…"
        case .cloudUnavailable, .failed: return "iCloud Sync Needs Attention"
        }
    }

    private var iCloudStatusSymbol: String {
        switch documentLibrary.state {
        case .localReady: return "iphone"
        case .cloudReady: return "checkmark.icloud"
        case .cloudUnavailable, .failed: return "exclamationmark.icloud"
        default: return "icloud"
        }
    }

    private func requestStorageMode(_ enabled: Bool) {
        iCloudConfirmation = enabled ? .enable : .disable
    }

    private func retryICloudAction() {
        if requestedStorageMode == .local {
            performMigration(to: .local)
        } else if documentLibrary.storageMode == .iCloud {
            Task { await documentLibrary.retryICloudAccess() }
        } else {
            performMigration(to: .iCloud)
        }
    }

    private func performMigration(to mode: DocumentStorageMode) {
        requestedStorageMode = mode
        Task {
            if mode == .iCloud {
                try? await documentLibrary.enableICloud()
            } else {
                try? await documentLibrary.disableICloud()
            }
        }
    }

    private func iCloudAlert(_ confirmation: ICloudSwitchConfirmation) -> Alert {
        switch confirmation {
        case .enable:
            return Alert(
                title: Text("Enable iCloud Sync?"),
                message: Text("Your local documents will be merged with iCloud. Existing files will not be overwritten."),
                primaryButton: .default(Text("Enable")) { performMigration(to: .iCloud) },
                secondaryButton: .cancel()
            )
        case .disable:
            return Alert(
                title: Text("Turn Off iCloud Sync?"),
                message: Text("A complete local copy will be downloaded first. Your iCloud documents will not be deleted."),
                primaryButton: .destructive(Text("Turn Off")) { performMigration(to: .local) },
                secondaryButton: .cancel()
            )
        }
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

private enum ICloudSwitchConfirmation: Int, Identifiable {
    case enable, disable
    var id: Int { rawValue }
}
