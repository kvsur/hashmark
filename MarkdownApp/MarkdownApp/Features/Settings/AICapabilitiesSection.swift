//
//  AICapabilitiesSection.swift
//  MarkdownApp
//
//  将用户 Web Search 偏好与 Registry 派生的实际可用性分开呈现。
//

import SwiftUI

struct AICapabilitiesSection: View {
    @Binding var webSearchEnabled: Bool
    @Binding var reasoningEffort: AIReasoningEffort
    let preview: AIConfigCapabilityPreview

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Web Search", isOn: $webSearchEnabled)
                capabilityDetail(
                    AICapabilityAvailability(preview.decisions[.nativeWebSearch]),
                    decision: preview.decisions[.nativeWebSearch]
                )
            }
            VStack(alignment: .leading, spacing: 6) {
                Picker("Reasoning Effort", selection: $reasoningEffort) {
                    ForEach(AIReasoningEffort.allCases) { effort in
                        Text(effortTitle(effort)).tag(effort)
                    }
                }
                .pickerStyle(.menu)
                capabilityDetail(
                    AICapabilityAvailability(preview.reasoning),
                    decision: preview.decisions[.reasoning]
                )
            }
            capabilityRow("Images", systemImage: "photo", capability: .imageInput)
            capabilityRow("PDFs", systemImage: "doc.richtext", capability: .pdfInput)
            capabilityRow("Files", systemImage: "doc", capability: .genericFileInput)
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
            VStack(alignment: .leading, spacing: 4) {
                Text("Capabilities depend on the provider, model, endpoint, and account. Unsupported fields are never sent.")
                Text("Reasoning stays on. Effort is mapped to the closest level supported by the selected provider and model.")
            }
        }
    }

    private func effortTitle(_ effort: AIReasoningEffort) -> LocalizedStringKey {
        switch effort {
        case .automatic: "Automatic"
        case .low: "Low"
        case .high: "High"
        case .maximum: "Maximum"
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
        capability: AIModelCapability
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Label(title, systemImage: systemImage)
            Spacer(minLength: 12)
            capabilityDetail(
                AICapabilityAvailability(preview.decisions[capability]),
                decision: preview.decisions[capability]
            )
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func capabilityDetail(
        _ availability: AICapabilityAvailability,
        decision: AICapabilityDecision?
    ) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Label {
                Text(statusTitle(availability))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: statusSymbol(availability))
                    .foregroundStyle(statusColor(availability))
            }
            .labelStyle(.titleAndIcon)
            if let decision {
                Text(decisionSourceTitle(decision))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private func statusTitle(_ availability: AICapabilityAvailability) -> LocalizedStringKey {
        switch availability {
        case .needsConfiguration: "Enter a valid endpoint and model to check availability."
        case .available: "Available"
        case .conditional: "Available with conditions"
        case .preferenceDisabled: "Off by preference"
        case .providerUnsupported: "Not available for this provider"
        case .modelNotVerified: "Not available for this model"
        case .unverified: "Unverified"
        case .separateServiceRequired: "Requires a separate provider service"
        case .incompatibleCombination: "Unavailable with this model combination"
        }
    }

    private func statusSymbol(_ availability: AICapabilityAvailability) -> String {
        switch availability {
        case .available: "checkmark.circle.fill"
        case .conditional: "checkmark.circle"
        case .needsConfiguration, .unverified: "questionmark.circle"
        case .preferenceDisabled: "pause.circle"
        case .providerUnsupported, .modelNotVerified, .separateServiceRequired,
             .incompatibleCombination: "minus.circle"
        }
    }

    private func statusColor(_ availability: AICapabilityAvailability) -> Color {
        switch availability {
        case .available: .green
        case .conditional: .orange
        case .unverified: .orange
        default: .secondary
        }
    }

    private func decisionSourceTitle(
        _ decision: AICapabilityDecision
    ) -> LocalizedStringKey {
        switch decision.source {
        case .providerMetadata: "Provider metadata"
        case .exactManifest: "Verified model rule"
        case .familyManifest: "Model family rule"
        case .runtimeVerification: "Runtime verification"
        case .conservativeFallback: "No capability evidence yet"
        }
    }
}
