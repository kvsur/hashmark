//
//  AICapabilitiesSection.swift
//  MarkdownApp
//
//  将用户 Web Search 偏好与 Registry 派生的实际可用性分开呈现。
//

import SwiftUI

struct AICapabilitiesSection: View {
    @Binding var webSearchEnabled: Bool
    let preview: AIConfigCapabilityPreview

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Web Search", isOn: $webSearchEnabled)
                capabilityDetail(AICapabilityAvailability(preview.webSearch))
            }
            capabilityRow("Thinking", systemImage: "ellipsis.bubble", capability: preview.reasoning)
            capabilityRow("Images", systemImage: "photo", capability: preview.imageInput)
            capabilityRow("PDFs", systemImage: "doc.richtext", capability: preview.inlinePDF)
            capabilityRow("Files", systemImage: "doc", capability: preview.files)
            if hasSearchReasoningConflict {
                Label {
                    Text("Web Search turns off visible thinking for this provider and model.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.orange)
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text("Capabilities")
        } footer: {
            Text("Capabilities depend on the provider, model, endpoint, and account. Unsupported fields are never sent.")
        }
    }

    private var hasSearchReasoningConflict: Bool {
        let search = AICapabilityAvailability(preview.webSearch)
        guard search == .available || search == .conditional else { return false }
        return AICapabilityAvailability(preview.reasoning) == .incompatibleCombination
    }

    private func capabilityRow(
        _ title: LocalizedStringKey,
        systemImage: String,
        capability: EffectiveCapability?
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Label(title, systemImage: systemImage)
            Spacer(minLength: 12)
            capabilityDetail(AICapabilityAvailability(capability))
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func capabilityDetail(_ availability: AICapabilityAvailability) -> some View {
        Label {
            Text(statusTitle(availability))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: statusSymbol(availability))
                .foregroundStyle(statusColor(availability))
        }
        .labelStyle(.titleAndIcon)
        .accessibilityLabel(statusTitle(availability))
    }

    private func statusTitle(_ availability: AICapabilityAvailability) -> LocalizedStringKey {
        switch availability {
        case .needsConfiguration: "Enter a valid endpoint and model to check availability."
        case .available: "Available"
        case .conditional: "Available with conditions"
        case .preferenceDisabled: "Off by preference"
        case .providerUnsupported: "Not available for this provider"
        case .modelNotVerified: "Not available for this model"
        case .separateServiceRequired: "Requires a separate provider service"
        case .incompatibleCombination: "Unavailable with this model combination"
        }
    }

    private func statusSymbol(_ availability: AICapabilityAvailability) -> String {
        switch availability {
        case .available: "checkmark.circle.fill"
        case .conditional: "checkmark.circle"
        case .needsConfiguration: "questionmark.circle"
        case .preferenceDisabled: "pause.circle"
        case .providerUnsupported, .modelNotVerified, .separateServiceRequired,
             .incompatibleCombination: "minus.circle"
        }
    }

    private func statusColor(_ availability: AICapabilityAvailability) -> Color {
        switch availability {
        case .available: .green
        case .conditional: .orange
        default: .secondary
        }
    }
}
