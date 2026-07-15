//
//  NameInputSheet.swift
//  MarkdownApp
//
//  通用的「输入名称」弹层，供 新建文件夹 / 新建文档 / 重命名 复用。
//  遵循 CLAUDE.md：抽成可复用组件，避免三处写重复的输入 UI。
//

import SwiftUI

struct NameInputSheet: View {
    let title: LocalizedStringKey
    let placeholder: LocalizedStringKey
    let onConfirm: (String) -> Void

    @State private var name: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    init(title: LocalizedStringKey, placeholder: LocalizedStringKey, initialName: String = "", onConfirm: @escaping (String) -> Void) {
        self.title = title
        self.placeholder = placeholder
        self.onConfirm = onConfirm
        _name = State(initialValue: initialName)
    }

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(placeholder, text: $name)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(confirm)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: confirm).disabled(trimmed.isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.height(180)])
        .rebuildsOnLanguageChange()
    }

    private func confirm() {
        guard !trimmed.isEmpty else { return }
        onConfirm(trimmed)
        dismiss()
    }
}
