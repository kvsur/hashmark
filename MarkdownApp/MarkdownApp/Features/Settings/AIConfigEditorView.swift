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
    private let consentStore: AIDataSharingConsentStore

    private enum PendingConsentAction {
        case refreshModels
    }

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
    @State private var hasDataSharingConsent: Bool
    @State private var pendingConsentAction: PendingConsentAction?
    /// iOS 16 的 onChange 只提供新值；显式保存上一个 Provider 以延续 profile 切换语义。
    @State private var previousProvider: AIProvider
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
        modelCatalogStore: AIModelCatalogStore = AIModelCatalogStore(),
        consentStore: AIDataSharingConsentStore = AIDataSharingConsentStore()
    ) {
        self.store = store
        self.modelCatalogStore = modelCatalogStore
        self.consentStore = consentStore
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
        _previousProvider = State(initialValue: loaded.provider)
        _hasDataSharingConsent = State(initialValue: consentStore.hasConsent(for: loaded))
    }

    var body: some View {
        NavigationStack {
            Form {
                providerSection
                AISupportedProvidersSection()
                modelSection
                endpointSection
                authenticationSection
                dataSharingSection
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
        .alert("AI Data Sharing", isPresented: consentPromptBinding) {
            Button("Not Now", role: .cancel) { pendingConsentAction = nil }
            Button("Allow and Continue") { allowPendingAction() }
        } message: {
            Text(AIDataSharingConsentCopy.message(for: draft))
        }
        .rebuildsOnLanguageChange()
        .onChange(of: draft.provider) { newValue in
            let oldValue = previousProvider
            guard oldValue != newValue else { return }
            previousProvider = newValue
            var outgoing = draft
            outgoing.provider = oldValue
            profileDrafts[oldValue] = outgoing
            let restored = profileDrafts[newValue] ?? store.load(provider: newValue)
            draft = AIConfigFormState.normalizedForEditing(restored)
            activeProfileID = store.profileID(for: newValue)
            loadCachedCatalog()
            refreshConsentStatus()
            modelRefreshMessage = nil
            isAdvancedEndpointExpanded = false
            focusedField = .model
        }
        .onChange(of: draft.baseURL) { _ in
            loadCachedCatalog()
            refreshConsentStatus()
        }
        .onChange(of: draft.model) { _ in syncSelectedModelMetadata() }
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
                    requestModelRefresh()
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

    private var dataSharingSection: some View {
        Section {
            LabeledContent("Destination") {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: draft.provider.displayName)
                    Text(verbatim: AIDataSharingRecipient(config: draft).displayEndpoint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            if hasDataSharingConsent {
                Label("Allowed for This Provider", systemImage: "checkmark.shield")
                    .foregroundStyle(.secondary)
                Button("Withdraw AI Data Sharing Consent", role: .destructive) {
                    consentStore.revoke(for: draft)
                    refreshConsentStatus()
                }
            } else {
                Label("Permission will be requested before connecting.", systemImage: "hand.raised")
                    .foregroundStyle(.secondary)
            }

            Link(destination: AppLinks.privacyPolicy) {
                Label("Privacy Policy", systemImage: "doc.text")
            }
        } header: {
            Text("Data Sharing")
        } footer: {
            Text("Withdrawing permission stops future requests to this provider and endpoint. It does not delete data already processed by the provider.")
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
            Button("Save") { requestSave() }
                .disabled(!formState.canSave)
                .accessibilityHint(formState.canSave
                    ? "Saves this AI configuration."
                    : "Resolve the configuration issues before saving.")
        }
    }

    private func requestSave() {
        guard formState.canSave else { return }
        save()
    }

    private func save() {
        do {
            try store.save(draft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func requestModelRefresh() {
        guard !isRefreshingModels else { return }
        guard consentStore.hasConsent(for: draft) else {
            pendingConsentAction = .refreshModels
            return
        }
        Task { await refreshModels() }
    }

    private func allowPendingAction() {
        guard let action = pendingConsentAction else { return }
        consentStore.grant(for: draft)
        pendingConsentAction = nil
        refreshConsentStatus()
        switch action {
        case .refreshModels:
            Task { await refreshModels() }
        }
    }

    private func refreshConsentStatus() {
        hasDataSharingConsent = consentStore.hasConsent(for: draft)
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

    private var consentPromptBinding: Binding<Bool> {
        Binding(
            get: { pendingConsentAction != nil },
            set: { if !$0 { pendingConsentAction = nil } }
        )
    }
}
