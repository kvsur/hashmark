//
//  AISearchSourcesView.swift
//  MarkdownApp
//
//  搜索状态与来源的独立旁路 UI；来源永不拼进生成正文。
//

import SwiftUI

struct AISearchSourcesView: View {
    let state: AISearchState
    let citations: [AISearchCitation]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isSearching {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Searching sources…")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            if !citations.isEmpty {
                Label("Sources", systemImage: "link")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(citations) { citation in
                            Link(destination: citation.url) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(citation.title)
                                        .font(.caption.weight(.medium))
                                        .lineLimit(1)
                                    if let publisher = citation.publisher, !publisher.isEmpty {
                                        Text(publisher)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(.secondary.opacity(0.1), in: .rect(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(citation.url.absoluteString)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, isSearching || !citations.isEmpty ? 10 : 0)
    }

    private var isSearching: Bool {
        switch state {
        case .searching, .awaitingContinuation: true
        case .idle, .completed: false
        }
    }
}
