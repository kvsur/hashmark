//
//  DocumentNameField.swift
//  MarkdownApp
//
//  预览与编辑态共用的文件名输入行；提交时机限定为 Return 或失焦。
//

import SwiftUI

struct DocumentNameField: View {
    @Binding var name: String
    let placeholder: String
    let isEnabled: Bool
    let isSubmitting: Bool
    let onCommit: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Document name", text: $name, prompt: Text(placeholder))
                .focused($isFocused)
                .submitLabel(.done)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled()
                .onSubmit {
                    onCommit()
                    isFocused = false
                }
                .onChange(of: isFocused) { focused in
                    if !focused { onCommit() }
                }
                .accessibilityLabel(Text("Document name"))
            if isSubmitting {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            }
        }
        .font(.body)
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        .disabled(!isEnabled || isSubmitting)
    }
}
