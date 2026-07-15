//
//  AIConfigEditorView.swift
//  MarkdownApp
//
//  AI 接口配置编辑器（modal）。以草稿副本编辑，「取消」丢弃不落盘、「保存」写本地。
//  读写走 AIConfigStore（存 Library/Application Support，不进 Documents）。
//

import SwiftUI

struct AIConfigEditorView: View {
    let store: AIConfigStore

    @Environment(\.dismiss) private var dismiss
    // 草稿副本：编辑期间只改这里，取消即整体丢弃，保存才落盘。
    @State private var draft = AIConfig.empty
    @State private var errorMessage: String?
    /// 观察 Base URL 的编辑焦点，用于在其失焦时按 URL 推断响应格式。
    @FocusState private var baseURLFocused: Bool
    /// 用户是否手动选过响应格式。手动选择优先于自动推断——
    /// 否则「自动切到 Claude → 用户改回 ChatGPT → 保存时又被切回」会把人锁死在推断结果上。
    @State private var formatChosenManually = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Base URL", text: $draft.baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .focused($baseURLFocused)
                    TextField("Model", text: $draft.model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Endpoint")
                } footer: {
                    Text("The base URL can point at the host root (e.g. https://api.anthropic.com) and the version and path are filled in automatically; a full endpoint URL also works.")
                }

                Section("Authentication") {
                    SecureField("API Key", text: $draft.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Response Format") {
                    // 经中转 Binding 而非直接绑 $draft.responseFormat：要区分「用户手动选的」
                    // 与「按 URL 自动推的」，手动选择优先，见 formatChosenManually。
                    Picker("Response Format", selection: Binding(
                        get: { draft.responseFormat },
                        set: { draft.responseFormat = $0; formatChosenManually = true }
                    )) {
                        ForEach(AIConfig.ResponseFormat.allCases) { format in
                            Text(format.label).tag(format)
                        }
                    }
                    .tallSegmentedPicker()
                }
            }
            .navigationTitle("AI Endpoint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // 关闭不保存：草稿随视图销毁丢弃。
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .alert("Save Failed", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .rebuildsOnLanguageChange()
        // 打开时载入现有配置到草稿（无则空表单）。
        .onAppear { draft = store.load() }
        // Base URL 编辑完（失焦）时按 URL 推断格式。选在失焦而非每次按键，
        // 是为了不在用户打字打到一半时跳动。
        .onChange(of: baseURLFocused) { wasFocused, isFocused in
            guard wasFocused, !isFocused else { return }
            applySuggestedFormat()
        }
    }

    /// 按 Base URL 推断响应格式并应用（推断规则见 AIConfig.suggestedResponseFormat）。
    /// 用户手动选过就不再干预；已经是该格式也什么都不做——免得白给一次触觉反馈让人以为动了什么。
    private func applySuggestedFormat() {
        guard !formatChosenManually,
              let suggested = draft.suggestedResponseFormat,
              draft.responseFormat != suggested
        else { return }
        draft.responseFormat = suggested
        Haptics.soft()   // 「状态悄然切换」，与预览↔编辑同一种手感
    }

    private func save() {
        // 兜底：只改了 Base URL 就直接点保存时，输入框从未失焦、onChange 不会触发，
        // 而这恰恰是最常见的编辑路径（改个地址就存）。此处再推一次，漏不掉。
        applySuggestedFormat()
        do {
            try store.save(draft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
