//
//  AIConfigEditorView.swift
//  MarkdownApp
//
//  五家原生 Provider 的统一配置页。用户不需要理解 wire protocol；
//  Provider 切换恢复稳定 profile；默认 endpoint/model 仅用于首次创建或明确 reset。
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
    @State private var profileDrafts: [AIProvider: AIConfig] = [:]
    @State private var activeProfileID = AIModelCatalogScope.legacyProfileID
    @State private var capabilityEvidence: [AICapabilityEvidence] = []
    @State private var errorMessage: String?
    @State private var discoveredModelIDs: [String] = []
    @State private var catalogSnapshot: AIModelCatalogSnapshot?
    @State private var isRefreshingModels = false
    @State private var modelRefreshMessage: String?
    @State private var isAdvancedEndpointExpanded = false
    @FocusState private var focusedField: Field?

    private let modelCatalog = AIModelCatalogService()

    private var formState: AIConfigFormState {
        AIConfigFormState(
            config: draft,
            catalogSnapshot: catalogSnapshot,
            profileID: activeProfileID,
            evidence: capabilityEvidence
        )
    }

    init(
        store: AIConfigStore,
        modelCatalogStore: AIModelCatalogStore = AIModelCatalogStore()
    ) {
        self.store = store
        self.modelCatalogStore = modelCatalogStore
        let document = store.loadDocument()
        let loaded = AIConfigFormState.normalizedForEditing(
            document.activeProfile?.config ?? .empty
        )
        let drafts = Dictionary(uniqueKeysWithValues: document.profiles.map {
            ($0.provider, $0.config)
        })
        let profileID = document.profile(for: loaded.provider)?.id
            ?? AIModelCatalogScope.legacyProfileID
        let snapshot = modelCatalogStore.snapshot(
            profileID: profileID,
            provider: loaded.provider,
            endpoint: loaded.baseURL
        )
        _draft = State(initialValue: loaded)
        _profileDrafts = State(initialValue: drafts)
        _activeProfileID = State(initialValue: profileID)
        _capabilityEvidence = State(initialValue: AICapabilityVerificationStore().allEvidence())
        _catalogSnapshot = State(initialValue: snapshot)
        _discoveredModelIDs = State(initialValue: snapshot?.modelIDs ?? [])
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
                    reasoningEffort: $draft.preferences.reasoningEffort,
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
            var outgoing = draft
            outgoing.provider = oldValue
            profileDrafts[oldValue] = outgoing
            let restored = profileDrafts[newValue] ?? store.load(provider: newValue)
            draft = AIConfigFormState.normalizedForEditing(restored)
            activeProfileID = store.profileID(for: newValue)
            loadCachedCatalog()
            modelRefreshMessage = nil
            isAdvancedEndpointExpanded = false
            focusedField = .model
        }
        .onChange(of: draft.baseURL) { _, _ in loadCachedCatalog() }
        .onChange(of: draft.model) { _, _ in syncSelectedModelMetadata() }
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
                status: formState.modelFreshness(catalogSnapshot: catalogSnapshot)
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
            Text("Available models come from your provider account. Capabilities use provider metadata, verified rules, and local results.")
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
            let profileID = activeProfileID
            let snapshot = try await modelCatalog.fetch(for: draft, profileID: profileID)
            guard snapshot.provider == requestedProvider, draft.provider == requestedProvider else { return }
            modelCatalogStore.save(snapshot)
            catalogSnapshot = modelCatalogStore.snapshot(
                profileID: profileID,
                provider: snapshot.provider,
                endpoint: draft.baseURL
            )
            discoveredModelIDs = catalogSnapshot?.modelIDs ?? snapshot.modelIDs
            syncSelectedModelMetadata()
            modelRefreshMessage = snapshot.modelIDs.isEmpty
                ? LocalizationController.string("No available models were returned.")
                : LocalizationController.string("Available models refreshed.")
        } catch {
            guard draft.provider == requestedProvider else { return }
            modelRefreshMessage = modelRefreshFailureMessage(error)
        }
    }

    private func loadCachedCatalog() {
        let profileID = activeProfileID
        catalogSnapshot = modelCatalogStore.snapshot(
            profileID: profileID,
            provider: draft.provider,
            endpoint: draft.baseURL
        )
        discoveredModelIDs = catalogSnapshot?.modelIDs ?? []
        syncSelectedModelMetadata()
    }

    private func syncSelectedModelMetadata() {
        let selected = catalogSnapshot?.models.first {
            $0.id.caseInsensitiveCompare(
                draft.model.trimmingCharacters(in: .whitespacesAndNewlines)
            ) == .orderedSame
        }
        draft.providerCapabilitySignals = selected?.metadata.capabilitySignals
        draft.providerMetadataObservedAt = selected?.lastSeenAt
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
            case .emptyResponse:
                return LocalizationController.string("No available models were returned.")
            case .paginationLimit:
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
