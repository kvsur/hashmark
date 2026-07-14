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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Base URL", text: $draft.baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Model", text: $draft.model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("接口")
                } footer: {
                    Text("Base URL 填到主机根即可（如 https://api.anthropic.com），会自动补全版本与端点；也可直接填完整端点地址。")
                }

                Section("鉴权") {
                    SecureField("API Key", text: $draft.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("响应格式") {
                    Picker("Response Format", selection: $draft.responseFormat) {
                        ForEach(AIConfig.ResponseFormat.allCases) { format in
                            Text(format.label).tag(format)
                        }
                    }
                    .tallSegmentedPicker()
                }
            }
            .navigationTitle("AI 接口配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // 关闭不保存：草稿随视图销毁丢弃。
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
            .alert("保存失败", isPresented: errorBinding) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        // 打开时载入现有配置到草稿（无则空表单）。
        .onAppear { draft = store.load() }
    }

    private func save() {
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
