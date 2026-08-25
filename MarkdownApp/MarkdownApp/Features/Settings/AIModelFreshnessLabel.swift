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
        case .discoveredStale: "Available from cached account data; the catalog is stale."
        case .missingCandidate: "Saved model is temporarily missing from the latest account catalog."
        case .deprecated: "This model is deprecated; keep it only for existing workflows."
        case .shutdown: "This model is shut down and can't be used."
        case .custom: "Custom model; advanced capabilities are unverified."
        }
    }

    private var symbol: String {
        switch status {
        case .manifestVerified: "checkmark.seal.fill"
        case .discoveredOnly: "info.circle"
        case .discoveredStale: "clock.badge.exclamationmark"
        case .missingCandidate: "questionmark.folder"
        case .deprecated: "exclamationmark.triangle"
        case .shutdown: "xmark.octagon"
        case .custom: "questionmark.circle"
        }
    }

    private var tint: Color {
        switch status {
        case .manifestVerified: .green
        case .discoveredOnly: .orange
        case .discoveredStale, .missingCandidate, .deprecated: .orange
        case .shutdown: .red
        case .custom: .secondary
        }
    }
}
