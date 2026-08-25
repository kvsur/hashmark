//
//  MarkdownOutlineSheet.swift
//  MarkdownApp
//
//  长文档标题导航；解析逻辑在 MarkdownOutline，视图只展示与回调。
//

import SwiftUI

struct MarkdownOutlineSheet: View {
    let markdown: String
    let onSelect: (MarkdownOutlineItem) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                let items = MarkdownOutline.items(in: markdown)
                if items.isEmpty {
                    ContentUnavailableView("No Headings", systemImage: "textformat.size")
                } else {
                    List(items) { item in
                        Button {
                            onSelect(item)
                            dismiss()
                        } label: {
                            Text(item.title)
                                .foregroundStyle(.primary)
                                .padding(.leading, CGFloat(item.level - 1) * 14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .navigationTitle("Outline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

