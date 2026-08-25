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
    search: Bool = true
) -> AIConfig {
    let manifest = AIProviderRegistry.manifest(for: provider)
    return AIConfig(
        provider: provider,
        baseURL: baseURL ?? manifest.defaultBaseURL,
        model: model ?? manifest.defaultModel,
        apiKey: apiKey,
        preferences: AICapabilityPreferences(webSearchEnabled: search)
    )
}

@main
enum AIConfigFormStateTests {
    static func main() async throws {
        expect(AIConfigFormState.providerOptions == AIProvider.allCases,
               "The settings form does not expose exactly six native Providers")

        for provider in AIProvider.allCases {
            let source = config(provider: provider, search: false)
            let changed = AIConfigFormState.applyingProvider(provider, to: source)
            let manifest = AIProviderRegistry.manifest(for: provider)
            expect(changed.provider == provider, "Provider selection was not saved")
            expect(changed.baseURL == manifest.defaultBaseURL, "Provider Base URL default changed")
            expect(changed.model == manifest.defaultModel, "Provider model default changed")
            expect(!changed.preferences.webSearchEnabled, "Provider switch overwrote search preference")
        }

        let normalized = AIConfigFormState.normalizedForEditing(.empty)
        expect(normalized.provider == .openAI, "Empty config did not retain the default Provider")
        expect(normalized.baseURL == AIProviderRegistry.manifest(for: .openAI).defaultBaseURL,
               "Empty config did not receive the OpenAI native endpoint")

        let valid = AIConfigFormState(config: config())
        expect(valid.canSave, "Valid native configuration cannot be saved")
        expect(valid.displayedProvider == .openAI, "Displayed Provider is not explicit")

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

        let qwen = AIConfigFormState(config: config(provider: .qwen))
        expect(qwen.manifest.defaultModel == "qwen3.7-plus",
               "Qwen settings default did not advance to qwen3.7-plus")
        expect(qwen.documentedModelIDs.contains("qwen3.8-max")
               && qwen.documentedModelIDs.contains("qwen3.6-flash"),
               "Qwen settings omitted the current 3.6-3.8 model families")
        expect(qwen.endpointPresets.map(\.id) == ["china", "singapore", "hong-kong", "united-states"],
               "Qwen regional endpoint presets changed")
        expect(AICapabilityAvailability(qwen.capabilityPreview.inlinePDF) == .conditional,
               "Qwen extraction-backed PDF attachment is hidden in Settings")
        expect(AIConfigFormState.applyingProvider(.qwen, to: config()).provider == .qwen,
               "Endpoint defaults changed Provider identity")

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
        try await testModelCatalogPagination()
        testModelCatalogPersistence()

        guard CommandLine.arguments.count == 4 else {
            failures.append("Settings source paths were not provided")
            finish()
            return
        }
        let editor = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
        let providers = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8)
        expect(editor.contains("ForEach(AIConfigFormState.providerOptions)"),
               "Provider picker is not driven by the six-case model")
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
        for provider in AIProvider.allCases {
            expect(providers.contains("AIProvider.officiallySupported") ||
                   providers.contains(provider.displayName),
                   "Supported list is not sourced from the six Providers")
        }
        finish()
    }

    private static func testModelCatalogContracts() throws {
        let routes: [(AIProvider, String, String)] = [
            (.openAI, "/v1/models", "Authorization"),
            (.anthropic, "/v1/models", "x-api-key"),
            (.gemini, "/v1beta/models", "x-goog-api-key"),
            (.qwen, "/api/v1/models/permissions", "Authorization"),
            (.kimi, "/v1/models", "Authorization")
        ]
        for (provider, path, authHeader) in routes {
            let request = try AIModelCatalogService.makeRequest(for: config(provider: provider))
            expect(request.url?.path == path, "\(provider.rawValue) model list path changed")
            expect(request.value(forHTTPHeaderField: authHeader)?.isEmpty == false,
                   "\(provider.rawValue) model list auth is missing")
        }
        let qwenRequest = try AIModelCatalogService.makeRequest(for: config(provider: .qwen))
        let qwenItems = URLComponents(url: qwenRequest.url!, resolvingAgainstBaseURL: false)?
            .queryItems ?? []
        expect(qwenItems.contains(URLQueryItem(name: "authorization_scope", value: "AUTHORIZED"))
               && qwenItems.contains(URLQueryItem(name: "action", value: "INFERENCE")),
               "Qwen China model refresh lost its account permission filters")

        let singapore = try AIModelCatalogService.makeRequest(for: config(
            provider: .qwen,
            baseURL: "https://dashscope-intl.aliyuncs.com/api/v1"
        ))
        let singaporeItems = URLComponents(url: singapore.url!, resolvingAgainstBaseURL: false)?
            .queryItems ?? []
        expect(singapore.url?.path == "/api/v1/models",
               "Qwen international model refresh left the regional list route")
        for item in [
            URLQueryItem(name: "providers", value: "qwen"),
            URLQueryItem(name: "capabilities", value: "TG"),
            URLQueryItem(name: "supports", value: "inference"),
            URLQueryItem(name: "page_no", value: "1")
        ] {
            expect(singaporeItems.contains(item),
                   "Qwen model list lost official query item \(item.name)")
        }

        let openAIData = #"{"data":[{"id":"gpt-5.6-terra"},{"id":"text-embedding-9"}]}"#.data(using: .utf8)!
        let openAIModels = try AIModelCatalogService.parseModelIDs(openAIData, provider: .openAI)
        expect(openAIModels == ["gpt-5.6-terra"],
               "OpenAI model discovery admitted a non-writing model")
        let geminiData = #"{"models":[{"name":"models/gemini-3.6-flash","baseModelId":"gemini-3.6-flash"},{"name":"models/gemini-3.8-flash","baseModelId":"gemini-3.8-flash"},{"name":"models/gemini-embedding-2-preview","baseModelId":"gemini-embedding-2-preview"},{"name":"models/gemini-3.1-flash-image","baseModelId":"gemini-3.1-flash-image"},{"name":"models/gemini-3.1-flash-lite","baseModelId":"gemini-3.1-flash-lite"}]}"#.data(using: .utf8)!
        let geminiModels = try AIModelCatalogService.parseModelIDs(geminiData, provider: .gemini)
        expect(geminiModels == ["gemini-3.1-flash-lite", "gemini-3.6-flash", "gemini-3.8-flash"],
               "Gemini discovery admitted a non-writing resource or lost a chat model")
        let qwenData = #"{"success":true,"output":{"total":1,"page_no":1,"page_size":100,"models":[{"model":"qwen3.8-max","provider":"qwen","capabilities":["TG"]}]}}"#.data(using: .utf8)!
        let qwenModels = try AIModelCatalogService.parseModelIDs(qwenData, provider: .qwen)
        expect(qwenModels == ["qwen3.8-max"],
               "Qwen current native model list schema was not parsed")
        let qwenPermissions = #"{"success":true,"output":{"total":1,"page_no":1,"page_size":200,"permissions":[{"model":"qwen3.7-plus","permissions":{"inference":true}}]}}"#.data(using: .utf8)!
        let permissionModels = try AIModelCatalogService.parseModelIDs(
            qwenPermissions,
            provider: .qwen
        )
        expect(permissionModels == ["qwen3.7-plus"],
               "Qwen China account permissions were not parsed")

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
    }

    private static func testModelCatalogPagination() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ModelCatalogURLProtocol.self]
        let session = URLSession(configuration: configuration)
        var requestedPages: [Int] = []
        ModelCatalogURLProtocol.handler = { request in
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            let page = Int(components?.queryItems?.first(where: {
                $0.name == "page_no"
            })?.value ?? "") ?? 1
            requestedPages.append(page)
            let model = page == 1 ? "qwen3.6-flash" : "qwen3.8-max"
            let data = Data(
                #"{"success":true,"output":{"total":2,"page_no":\#(page),"page_size":1,"models":[{"model":"\#(model)"}]}}"#.utf8
            )
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!,
                data
            )
        }
        defer {
            ModelCatalogURLProtocol.handler = nil
            session.invalidateAndCancel()
        }

        let snapshot = try await AIModelCatalogService(session: session).fetch(for: config(
            provider: .qwen,
            baseURL: "https://dashscope-intl.aliyuncs.com/api/v1"
        ))
        expect(requestedPages == [1, 2],
               "Qwen model refresh did not follow the native catalog pagination")
        expect(snapshot.modelIDs == ["qwen3.6-flash", "qwen3.8-max"],
               "Qwen paginated model refresh lost current models")
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
