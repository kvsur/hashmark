import Foundation

private var failures: [String] = []

private final class ModelCatalogURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw URLError(.badServerResponse)
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { failures.append(message) }
}

private func config(
    provider: AIProvider = .openAI,
    baseURL: String? = nil,
    model: String? = nil,
    apiKey: String = "fixture-key",
    search: Bool = true,
    reasoningEffort: AIReasoningEffort = .low
) -> AIConfig {
    let manifest = AIProviderRegistry.manifest(for: provider)
    return AIConfig(
        provider: provider,
        baseURL: baseURL ?? manifest.defaultBaseURL,
        model: model ?? manifest.defaultModel,
        apiKey: apiKey,
        preferences: AICapabilityPreferences(
            webSearchEnabled: search,
            reasoningEffort: reasoningEffort
        )
    )
}

@main
enum AIConfigFormStateTests {
    static func main() async throws {
        expect(AIConfigFormState.providerOptions == AIProvider.allCases,
               "The settings form does not expose exactly five native Providers")

        for provider in AIProvider.allCases {
            let source = config(provider: provider, search: false)
            let changed = AIConfigFormState.applyingProvider(provider, to: source)
            let manifest = AIProviderRegistry.manifest(for: provider)
            expect(changed.provider == provider, "Provider selection was not saved")
            expect(changed.baseURL == manifest.defaultBaseURL, "Provider Base URL default changed")
            expect(changed.model == manifest.defaultModel, "Provider model default changed")
            expect(!changed.preferences.webSearchEnabled, "Provider switch overwrote search preference")
            expect(changed.preferences.reasoningEffort == .low,
                   "Provider switch overwrote Reasoning Effort")
        }

        let normalized = AIConfigFormState.normalizedForEditing(.empty)
        expect(normalized.provider == .openAI, "Empty config did not retain the default Provider")
        expect(normalized.baseURL == AIProviderRegistry.manifest(for: .openAI).defaultBaseURL,
               "Empty config did not receive the OpenAI native endpoint")

        let valid = AIConfigFormState(config: config())
        expect(valid.canSave, "Valid native configuration cannot be saved")
        expect(valid.displayedProvider == .openAI, "Displayed Provider is not explicit")

        let lowReasoning = AIConfigFormState(config: config(reasoningEffort: .low))
        let lowReasoningAvailability = AICapabilityAvailability(
            lowReasoning.capabilityPreview.reasoning
        )
        expect(lowReasoningAvailability == .available
               || lowReasoningAvailability == .conditional,
               "Changing Reasoning Effort incorrectly disabled Thinking")

        let unknown = AIConfigFormState(config: config(model: "unknown-model"))
        expect(AICapabilityAvailability(unknown.capabilityPreview.webSearch) == .modelNotVerified,
               "Unknown model received search availability")
        expect(unknown.modelFreshness == .custom,
               "Unknown model was presented as manifest-verified")
        expect(unknown.modelOptions(discoveredModelIDs: []).contains("unknown-model"),
               "The saved dynamic model disappeared from model choices")

        let openAI = AIConfigFormState(config: config(provider: .openAI))
        expect(openAI.modelFreshness == .manifestVerified(date: "2026-08-24"),
               "Dated model verification was not exposed")
        expect(openAI.documentedModelIDs.contains("gpt-5.6-terra"),
               "Manifest model choices are missing the Provider default")

        for model in ["kimi-k2.5", "kimi-k3"] {
            let kimi = AIConfigFormState(config: config(
                provider: .kimi,
                model: model,
                search: false
            ))
            expect(AICapabilityAvailability(kimi.capabilityPreview.imageInput) == .conditional,
                   "\(model) image input is hidden in Settings")
            expect(AICapabilityAvailability(kimi.capabilityPreview.inlinePDF) == .available,
                   "\(model) extraction-backed PDF input is hidden in Settings")
            expect(AICapabilityAvailability(kimi.capabilityPreview.files) == .available,
                   "\(model) Provider-level Files service is hidden in Settings")
        }

        let gemini = AIConfigFormState(config: config(
            provider: .gemini,
            model: "gemini-3.1-flash-lite"
        ))
        expect(gemini.documentedModelIDs.contains("gemini-3.1-flash-lite"),
               "Gemini settings omitted the current 3.1 Flash-Lite model")
        expect(!gemini.documentedModelIDs.contains("gemini-2.0-flash"),
               "Gemini settings still exposes a shut-down 2.0 model")

        let glm = AIConfigFormState(config: config(
            provider: .glm,
            model: "glm-4.6v-flash"
        ))
        expect(AICapabilityAvailability(glm.capabilityPreview.imageInput) == .conditional,
               "GLM 4.6V Flash image input is hidden in Settings")
        expect(AICapabilityAvailability(glm.capabilityPreview.inlinePDF) == .conditional,
               "GLM 4.6V Flash file input is hidden in Settings")

        try testModelCatalogContracts()
        try await testModelCatalogPaginationAndMetadata()
        testModelCatalogPersistence()
        testSettingsLifecycleStates()

        guard CommandLine.arguments.count == 4 else {
            failures.append("Settings source paths were not provided")
            finish()
            return
        }
        let editor = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
        let providers = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8)
        let capabilities = try String(contentsOfFile: CommandLine.arguments[3], encoding: .utf8)
        expect(editor.contains("ForEach(AIConfigFormState.providerOptions)"),
               "Provider picker is not driven by the five-case model")
        expect(!editor.contains("APIProtocol") && !editor.contains("protocolSection"),
               "Compatibility protocol UI is still present")
        expect(!editor.contains("Provider Override") && !editor.contains("Automatic detects"),
               "Host detection or gateway Provider override is still visible")
        expect(editor.contains("SecureField(\"API Key\"") && editor.contains("Refresh Available Models"),
               "Settings did not provide private credentials and explicit model refresh")
        expect(editor.contains("State(initialValue: loaded)"),
               "Settings no longer initializes directly from the saved configuration")
        expect(!editor.contains(".onAppear {\n            draft ="),
               "Programmatic config loading can still trigger a false Provider switch")
        expect(editor.contains("modelCatalogStore.save(snapshot)"),
               "Refreshed model catalogs are not persisted")
        expect(editor.contains("reasoningEffort: $draft.preferences.reasoningEffort")
               && capabilities.contains("Picker(\"Reasoning Effort\"")
               && !capabilities.contains("Toggle(\"Thinking\""),
               "Endpoint settings do not expose the persisted Effort picker")
        for provider in AIProvider.allCases {
            expect(providers.contains("AIProvider.officiallySupported") ||
                   providers.contains(provider.displayName),
                   "Supported list is not sourced from the five Providers")
        }
        finish()
    }

    private static func testModelCatalogContracts() throws {
        let routes: [(AIProvider, String, String)] = [
            (.openAI, "/v1/models", "Authorization"),
            (.anthropic, "/v1/models", "x-api-key"),
            (.gemini, "/v1beta/models", "x-goog-api-key"),
            (.kimi, "/v1/models", "Authorization")
        ]
        for (provider, path, authHeader) in routes {
            let request = try AIModelCatalogService.makeRequest(for: config(provider: provider))
            expect(request.url?.path == path, "\(provider.rawValue) model list path changed")
            expect(request.value(forHTTPHeaderField: authHeader)?.isEmpty == false,
                   "\(provider.rawValue) model list auth is missing")
        }
        let openAIData = #"{"data":[{"id":"gpt-5.6-terra"},{"id":"text-embedding-9"}]}"#.data(using: .utf8)!
        let openAIModels = try AIModelCatalogService.parseModelIDs(openAIData, provider: .openAI)
        expect(openAIModels == ["gpt-5.6-terra", "text-embedding-9"],
               "OpenAI ID-only discovery discarded an account-visible model")
        let geminiData = #"{"models":[{"name":"models/gemini-3.6-flash","baseModelId":"gemini-3.6-flash","supportedGenerationMethods":["generateContent"]},{"name":"models/gemini-3.8-flash","baseModelId":"gemini-3.8-flash","supportedGenerationMethods":["generateContent"]},{"name":"models/gemini-embedding-2-preview","baseModelId":"gemini-embedding-2-preview","supportedGenerationMethods":["embedContent"]},{"name":"models/gemini-3.1-flash-image","baseModelId":"gemini-3.1-flash-image","supportedGenerationMethods":["predict"]},{"name":"models/gemini-3.1-flash-lite","baseModelId":"gemini-3.1-flash-lite","supportedGenerationMethods":["streamGenerateContent"]}]}"#.data(using: .utf8)!
        let geminiModels = try AIModelCatalogService.parseModelIDs(geminiData, provider: .gemini)
        expect(geminiModels == ["gemini-3.1-flash-lite", "gemini-3.6-flash", "gemini-3.8-flash"],
               "Gemini discovery admitted a non-writing resource or lost a chat model")
        do {
            _ = try AIModelCatalogService.makeRequest(for: config(provider: .glm))
            failures.append("GLM undocumented model discovery was guessed")
        } catch AIModelCatalogError.unavailable {
            // Expected: the UI keeps the dated manifest without inventing a list route.
        }
    }

    private static func testModelCatalogPersistence() {
        let suiteName = "AIModelCatalogStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            failures.append("Could not create isolated model catalog defaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AIModelCatalogStore(defaults: defaults)
        store.save(AIModelCatalogSnapshot(
            provider: .kimi,
            modelIDs: ["kimi-k3", "kimi-k2.6", "kimi-k3", "  "],
            fetchedAt: Date(timeIntervalSince1970: 1)
        ))
        expect(store.modelIDs(for: .kimi) == ["kimi-k2.6", "kimi-k3"],
               "Kimi refreshed models did not survive a catalog reload")
        expect(store.modelIDs(for: .gemini).isEmpty,
               "A refreshed model catalog leaked across Providers")

        store.save(AIModelCatalogSnapshot(
            provider: .gemini,
            modelIDs: ["gemini-3.7-flash"],
            fetchedAt: Date(timeIntervalSince1970: 2)
        ))
        expect(store.modelIDs(for: .kimi).contains("kimi-k3"),
               "Saving another Provider erased the Kimi model catalog")

        let profileA = UUID()
        let profileB = UUID()
        let first = AIModelCatalogSnapshot(
            profileID: profileA,
            provider: .openAI,
            normalizedEndpoint: "https://api.openai.com/v1",
            models: [AIModelDiscoveryParsing.descriptor(
                id: "gpt-first",
                observedAt: Date(timeIntervalSince1970: 3)
            )],
            fetchedAt: Date(timeIntervalSince1970: 3)
        )
        store.save(first)
        store.save(AIModelCatalogSnapshot(
            profileID: profileA,
            provider: .openAI,
            normalizedEndpoint: "https://api.openai.com/v1",
            models: [],
            fetchedAt: Date(timeIntervalSince1970: 4)
        ))
        expect(store.modelIDs(
            profileID: profileA,
            provider: .openAI,
            endpoint: "https://api.openai.com/v1/"
        ) == ["gpt-first"], "An empty refresh destroyed last-good")
        expect(store.modelIDs(
            profileID: profileB,
            provider: .openAI,
            endpoint: "https://api.openai.com/v1"
        ).isEmpty, "Catalog cache leaked across profiles")

        let second = AIModelCatalogSnapshot(
            profileID: profileA,
            provider: .openAI,
            normalizedEndpoint: "https://api.openai.com/v1",
            models: [AIModelDiscoveryParsing.descriptor(
                id: "gpt-second",
                observedAt: Date(timeIntervalSince1970: 5)
            )],
            fetchedAt: Date(timeIntervalSince1970: 5)
        )
        let diff = store.save(second)
        expect(diff?.added == ["gpt-second"] && diff?.missing == ["gpt-first"],
               "Catalog diff did not report added and missing IDs")
        expect(store.modelIDs(
            profileID: profileA,
            provider: .openAI,
            endpoint: "https://api.openai.com/v1"
        ) == ["gpt-first", "gpt-second"],
               "A single missing catalog result erased last-good")
        expect(first.isStale(at: Date(timeIntervalSince1970: 3 + 86_401)),
               "Catalog TTL did not mark stale data")

        let legacyData = try? JSONSerialization.data(withJSONObject: [
            "modelIDsByProvider": ["anthropic": ["claude-legacy"]]
        ])
        defaults.set(legacyData, forKey: "AIModelCatalog.v1")
        expect(store.modelIDs(for: .anthropic) == ["claude-legacy"],
               "v1 Provider catalog did not migrate on read")
    }

    private static func testSettingsLifecycleStates() {
        let profileID = UUID()
        let model = "gpt-account-state"
        let state = AIConfigFormState(config: config(model: model), profileID: profileID)
        func snapshot(
            lifecycle: AIModelLifecycle = .active,
            missingCount: Int = 0,
            fetchedAt: Date = .now
        ) -> AIModelCatalogSnapshot {
            AIModelCatalogSnapshot(
                profileID: profileID,
                provider: .openAI,
                normalizedEndpoint: "https://api.openai.com/v1",
                models: [AIModelDescriptor(
                    id: model,
                    displayName: "Account State",
                    metadata: AIModelProviderMetadata(),
                    lifecycle: lifecycle,
                    source: .providerAPI,
                    firstSeenAt: fetchedAt,
                    lastSeenAt: fetchedAt,
                    missingCount: missingCount
                )],
                fetchedAt: fetchedAt
            )
        }

        expect(state.modelFreshness(catalogSnapshot: snapshot()) == .discoveredOnly,
               "Fresh discovered Settings state changed")
        expect(state.modelFreshness(catalogSnapshot: snapshot(
            fetchedAt: .now.addingTimeInterval(-AIModelCatalogSnapshot.cacheTTL - 1)
        )) == .discoveredStale, "Stale discovered Settings state changed")
        expect(state.modelFreshness(catalogSnapshot: snapshot(missingCount: 1)) == .missingCandidate,
               "Missing-candidate Settings state changed")
        expect(state.modelFreshness(catalogSnapshot: snapshot(lifecycle: .deprecated)) == .deprecated,
               "Deprecated Settings state changed")
        expect(state.modelFreshness(catalogSnapshot: snapshot(lifecycle: .shutdown)) == .shutdown,
               "Shutdown Settings state changed")
        expect(state.modelFreshness(catalogSnapshot: nil) == .custom,
               "Custom Settings state changed")
        expect(AICapabilityAvailability(state.capabilityPreview.decisions[.imageInput]) == .unverified,
               "Unverified capability Settings state changed")
    }

    private static func testModelCatalogPaginationAndMetadata() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ModelCatalogURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer {
            ModelCatalogURLProtocol.handler = nil
            session.invalidateAndCancel()
        }

        var anthropicCursors: [String] = []
        ModelCatalogURLProtocol.handler = { request in
            let cursor = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "after_id" })?.value
            anthropicCursors.append(cursor ?? "first")
            let data = cursor == nil
                ? Data(#"{"data":[{"id":"claude-first","display_name":"First","created_at":"2026-08-25T00:00:00Z","capabilities":{"image_input":true,"pdf_input":true,"thinking":true}}],"has_more":true,"last_id":"claude-first"}"#.utf8)
                : Data(#"{"data":[{"id":"claude-second","capabilities":{"image_input":false}}],"has_more":false,"last_id":"claude-second"}"#.utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data
            )
        }
        let anthropic = try await AIModelCatalogService(
            session: session,
            now: { Date(timeIntervalSince1970: 10) }
        ).fetch(for: config(provider: .anthropic))
        expect(anthropicCursors == ["first", "claude-first"],
               "Anthropic cursor pagination did not follow last_id")
        expect(anthropic.modelIDs == ["claude-first", "claude-second"],
               "Anthropic paginated models were lost")
        expect(anthropic.models.first(where: { $0.id == "claude-first" })?
            .metadata.capabilitySignals[.imageInput] == true,
               "Anthropic capability metadata was dropped")

        var geminiTokens: [String] = []
        ModelCatalogURLProtocol.handler = { request in
            let token = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "pageToken" })?.value
            geminiTokens.append(token ?? "first")
            let data = token == nil
                ? Data(#"{"models":[{"name":"models/gemini-first","baseModelId":"gemini-first","inputTokenLimit":100,"supportedGenerationMethods":["generateContent"],"thinking":true}],"nextPageToken":"next"}"#.utf8)
                : Data(#"{"models":[{"name":"models/gemini-second","baseModelId":"gemini-second","supportedGenerationMethods":["streamGenerateContent"]}]}"#.utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data
            )
        }
        let gemini = try await AIModelCatalogService(
            session: session,
            now: { Date(timeIntervalSince1970: 11) }
        ).fetch(for: config(provider: .gemini))
        expect(geminiTokens == ["first", "next"],
               "Gemini pageToken pagination was not followed")
        expect(gemini.modelIDs == ["gemini-first", "gemini-second"],
               "Gemini paginated models were lost")
        expect(gemini.models.first?.metadata.inputTokenLimit == 100,
               "Gemini token metadata was dropped")
    }

    private static func finish() {
        if failures.isEmpty {
            print("AIConfigFormStateTests: PASS")
        } else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
    }
}
