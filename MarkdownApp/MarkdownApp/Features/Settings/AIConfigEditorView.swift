//
//  AIConfigEditorView.swift
//  MarkdownApp
//
//  六家原生 Provider 的统一配置页。用户不需要理解 wire protocol；
//  Provider 切换只更新该服务的第一方 endpoint/model 默认值。
//

import SwiftUI

struct AIConfigEditorView: View {
    let store: AIConfigStore
    private let modelCatalogStore: AIModelCatalogStore

    private enum Field: Hashable {
        case baseURL, model, apiKey
    }

    @Environment(\.dismiss) private var dismiss
    @State private var draft = AIConfig.empty
    @State private var errorMessage: String?
    @State private var discoveredModelIDs: [String] = []
    @State private var isRefreshingModels = false
    @State private var modelRefreshMessage: String?
    @State private var isAdvancedEndpointExpanded = false
    @FocusState private var focusedField: Field?

    private let modelCatalog = AIModelCatalogService()

    private var formState: AIConfigFormState { AIConfigFormState(config: draft) }

    init(
        store: AIConfigStore,
        modelCatalogStore: AIModelCatalogStore = AIModelCatalogStore()
    ) {
        self.store = store
        self.modelCatalogStore = modelCatalogStore
        let loaded = AIConfigFormState.normalizedForEditing(store.load())
        _draft = State(initialValue: loaded)
        _discoveredModelIDs = State(
            initialValue: modelCatalogStore.modelIDs(for: loaded.provider)
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                providerSection
                AISupportedProvidersSection()
                modelSection
                endpointSection
                authenticationSection
                AICapabilitiesSection(
                    webSearchEnabled: $draft.preferences.webSearchEnabled,
                    preview: formState.capabilityPreview
                )
                validationSection
            }
            .navigationTitle("AI Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .alert("Save Failed", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .rebuildsOnLanguageChange()
        .onChange(of: draft.provider) { oldValue, newValue in
            guard oldValue != newValue else { return }
            draft = AIConfigFormState.applyingProvider(newValue, to: draft)
            discoveredModelIDs = modelCatalogStore.modelIDs(for: newValue)
            modelRefreshMessage = nil
            isAdvancedEndpointExpanded = false
            focusedField = .model
        }
    }

    private var providerSection: some View {
        Section("Provider") {
            Picker("Provider", selection: $draft.provider) {
                ForEach(AIConfigFormState.providerOptions) { provider in
                    Text(verbatim: provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.menu)
            .accessibilityHint("Choose how the app connects to your AI provider.")
        }
    }

    private var modelSection: some View {
        Section {
            TextField("Model", text: $draft.model)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .model)
                .submitLabel(.next)
                .onSubmit { focusedField = .apiKey }

            if !formState.modelOptions(discoveredModelIDs: discoveredModelIDs).isEmpty {
                Menu {
                    ForEach(formState.modelOptions(discoveredModelIDs: discoveredModelIDs), id: \.self) { modelID in
                        Button {
                            draft.model = modelID
                        } label: {
                            Text(verbatim: modelID)
                        }
                    }
                } label: {
                    Label("Choose Model", systemImage: "list.bullet")
                }
            }

            AIModelFreshnessLabel(
                status: formState.modelFreshness(discoveredModelIDs: discoveredModelIDs)
            )

            if formState.supportsModelRefresh {
                Button {
                    Task { await refreshModels() }
                } label: {
                    if isRefreshingModels {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Refreshing Models…")
                        }
                    } else {
                        Label("Refresh Available Models", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshingModels || draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let modelRefreshMessage {
                Text(modelRefreshMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Model")
        } footer: {
            Text("Available models come from your provider account. Advanced capabilities still follow the dated verified list.")
        }
    }

    private var endpointSection: some View {
        Section("Endpoint") {
            if formState.endpointPresets.count > 1 {
                Picker("Region", selection: endpointPresetSelection) {
                    ForEach(formState.endpointPresets) { preset in
                        Text(LocalizedStringKey(preset.displayName)).tag(preset.id)
                    }
                    Text("Custom").tag("custom")
                }
                .pickerStyle(.menu)
            } else if let preset = formState.endpointPresets.first {
                LabeledContent("Region") {
                    Text(LocalizedStringKey(preset.displayName))
                        .foregroundStyle(.secondary)
                }
            }

            DisclosureGroup("Advanced", isExpanded: $isAdvancedEndpointExpanded) {
                TextField("Base URL", text: $draft.baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .focused($focusedField, equals: .baseURL)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
                Text("A custom Base URL only changes where this provider connects. It never changes the provider or API format.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var authenticationSection: some View {
        Section("Authentication") {
            SecureField("API Key", text: $draft.apiKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.password)
                .focused($focusedField, equals: .apiKey)
                .submitLabel(.done)
                .onSubmit { focusedField = nil }
                .accessibilityHint("Stored only in this app's local configuration.")
        }
    }

    @ViewBuilder
    private var validationSection: some View {
        if !formState.validationIssues.isEmpty {
            Section("Configuration Issues") {
                ForEach(Array(formState.validationIssues.enumerated()), id: \.offset) { _, issue in
                    Label {
                        Text(validationTitle(issue))
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") { save() }
                .disabled(!formState.canSave)
                .accessibilityHint(formState.canSave
                    ? "Saves this AI configuration."
                    : "Resolve the configuration issues before saving.")
        }
    }

    private func save() {
        guard formState.canSave else { return }
        do {
            try store.save(draft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var endpointPresetSelection: Binding<String> {
        Binding(
            get: {
                formState.endpointPresets.first(where: {
                    normalizedURL($0.baseURL) == normalizedURL(draft.baseURL)
                })?.id ?? "custom"
            },
            set: { id in
                guard let preset = formState.endpointPresets.first(where: { $0.id == id }) else {
                    isAdvancedEndpointExpanded = true
                    return
                }
                draft.baseURL = preset.baseURL
            }
        )
    }

    private func refreshModels() async {
        guard !isRefreshingModels else { return }
        let requestedProvider = draft.provider
        isRefreshingModels = true
        modelRefreshMessage = nil
        defer { isRefreshingModels = false }
        do {
            let snapshot = try await modelCatalog.fetch(for: draft)
            guard snapshot.provider == requestedProvider, draft.provider == requestedProvider else { return }
            modelCatalogStore.save(snapshot)
            discoveredModelIDs = snapshot.modelIDs
            modelRefreshMessage = snapshot.modelIDs.isEmpty
                ? LocalizationController.string("No available models were returned.")
                : LocalizationController.string("Available models refreshed.")
        } catch {
            guard draft.provider == requestedProvider else { return }
            modelRefreshMessage = modelRefreshFailureMessage(error)
        }
    }

    private func modelRefreshFailureMessage(_ error: Error) -> String {
        if let issue = error as? AIModelCatalogError {
            switch issue {
            case .unavailable:
                return LocalizationController.string("Model refresh isn't available for this provider.")
            case .invalidEndpoint:
                return LocalizationController.string("Check the Base URL before refreshing models.")
            case .invalidResponse:
                return LocalizationController.string("The provider returned an unreadable model list.")
            case .http:
                return LocalizationController.string("The provider couldn't refresh models. Check your API Key and region.")
            }
        }
        return error.localizedDescription
    }

    private func normalizedURL(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }

    private func validationTitle(_ issue: AIConfigValidationIssue) -> LocalizedStringKey {
        switch issue {
        case .missingBaseURL: "Enter a Base URL."
        case .missingModel: "Enter a model."
        case .missingAPIKey: "Enter an API Key."
        case .invalidBaseURL: "Enter a valid Base URL."
        case .unsupportedURLScheme: "Use an HTTP or HTTPS Base URL."
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
