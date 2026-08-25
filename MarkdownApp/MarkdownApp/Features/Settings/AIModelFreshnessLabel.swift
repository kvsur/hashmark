//
//  AIModelFreshnessLabel.swift
//  MarkdownApp
//
//  Dated manifest authority versus account-discovered/custom model status.
//

import SwiftUI

struct AIModelFreshnessLabel: View {
    let status: AIModelFreshnessStatus

    var body: some View {
        Label {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(tint)
        }
        .accessibilityElement(children: .combine)
    }

    private var title: LocalizedStringKey {
        switch status {
        case .manifestVerified(let date): "Capabilities verified on \(date)"
        case .discoveredOnly: "Available to this account; advanced capabilities aren't verified."
        case .custom: "Custom model; advanced capabilities stay off until the verified list is updated."
        }
    }

    private var symbol: String {
        switch status {
        case .manifestVerified: "checkmark.seal.fill"
        case .discoveredOnly: "info.circle"
        case .custom: "questionmark.circle"
        }
    }

    private var tint: Color {
        switch status {
        case .manifestVerified: .green
        case .discoveredOnly: .orange
        case .custom: .secondary
        }
    }
}
