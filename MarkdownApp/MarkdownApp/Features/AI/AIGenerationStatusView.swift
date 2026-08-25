//
//  AIGenerationStatusView.swift
//  MarkdownApp
//
//  Compact, non-technical progress for phases that do not have richer dedicated UI.
//

import SwiftUI

struct AIGenerationStatusView: View {
    let phase: AIPresentationPhase

    var body: some View {
        if let content {
            HStack(spacing: 10) {
                if phase.isActive {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: content.symbol)
                        .foregroundStyle(content.tint)
                        .accessibilityHidden(true)
                }
                Text(content.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private var content: (title: LocalizedStringKey, symbol: String, tint: Color)? {
        switch phase {
        case .idle, .searching, .generating, .completed:
            nil
        case .preparingAttachments:
            ("Preparing attachments…", "paperclip", .secondary)
        case .uploading:
            ("Uploading attachments…", "icloud.and.arrow.up", .secondary)
        case .connecting:
            ("Connecting…", "antenna.radiowaves.left.and.right", .secondary)
        case .thinking:
            ("Thinking…", "ellipsis", .secondary)
        case .usingTool:
            ("Using a tool…", "wrench.and.screwdriver", .secondary)
        case .finalizing:
            ("Finishing the answer…", "checkmark.circle", .secondary)
        case .awaitingInput:
            ("Waiting for your answer", "questionmark.bubble", Theme.aiAccent)
        case .cancelled:
            ("Generation stopped", "stop.circle", .orange)
        case .interrupted:
            ("Generation Interrupted", "wifi.exclamationmark", .orange)
        case .failed:
            ("Generation Failed", "exclamationmark.triangle", .red)
        }
    }
}
