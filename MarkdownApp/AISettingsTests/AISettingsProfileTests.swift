import Foundation

private var failures: [String] = []

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { failures.append(message) }
}

private func matchesPersistedFields(_ lhs: AIConfig?, _ rhs: AIConfig) -> Bool {
    guard let lhs else { return false }
    return lhs.provider == rhs.provider
        && lhs.baseURL == rhs.baseURL
        && lhs.model == rhs.model
        && lhs.apiKey == rhs.apiKey
        && lhs.preferences == rhs.preferences
        && lhs.providerCapabilitySignals == rhs.providerCapabilitySignals
        && lhs.providerMetadataObservedAt == rhs.providerMetadataObservedAt
}

@main
enum AISettingsProfileTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AISettingsProfileTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let migrationDate = Date(timeIntervalSince1970: 100)
        let legacy = AIConfig(
            provider: .gemini,
            baseURL: "https://gateway.example/gemini",
            model: "gemini-future-account-model",
            apiKey: "legacy-secret",
            preferences: AICapabilityPreferences(webSearchEnabled: false)
        )
        try JSONEncoder().encode(legacy).write(
            to: directory.appendingPathComponent("AIConfig.json"),
            options: .atomic
        )

        let store = AIConfigStore(
            directoryURL: directory,
            now: { migrationDate }
        )
        let migrated = store.loadDocument()
        expect(migrated.schemaVersion == 2 && migrated.profiles.count == 5,
               "Legacy config did not create five versioned profiles")
        expect(migrated.migratedFromLegacy, "Migration provenance was not recorded")
        expect(matchesPersistedFields(migrated.activeProfile?.config, legacy),
               "Legacy provider/model/endpoint/key/preferences migration was lossy")
        expect(migrated.profiles.allSatisfy {
            $0.preferences.reasoningEffort == .low
        }, "Profiles did not default Reasoning Effort to Low")
        expect(AICapabilityPreferences().reasoningEffort == .low,
               "The Reasoning Effort preference did not default to Low")
        let geminiID = migrated.profile(for: .gemini)?.id
        expect(store.loadDocument().profile(for: .gemini)?.id == geminiID,
               "Profile identity changed after Store reconstruction")

        var kimi = store.load(provider: .kimi)
        kimi.model = "kimi-newly-discovered"
        kimi.baseURL = "https://gateway.example/kimi"
        kimi.apiKey = "kimi-key"
        kimi.preferences.webSearchEnabled = true
        kimi.preferences.reasoningEffort = .low
        kimi.providerCapabilitySignals = [.imageInput: true, .pdfInput: false]
        kimi.providerMetadataObservedAt = Date(timeIntervalSince1970: 99)
        try store.save(kimi)

        var openAI = store.load(provider: .openAI)
        openAI.model = "gpt-account-only"
        openAI.apiKey = "openai-key"
        try store.save(openAI)

        let rebuilt = AIConfigStore(directoryURL: directory, now: { migrationDate })
        expect(rebuilt.load(provider: .kimi) == kimi,
               "Provider round-trip did not restore the Kimi profile")
        expect(rebuilt.load(provider: .openAI) == openAI,
               "Dynamic OpenAI model did not survive save/reload")
        expect(matchesPersistedFields(rebuilt.load(provider: .gemini), legacy),
               "Saving another Provider overwrote the migrated Gemini profile")
        expect(rebuilt.load().provider == .openAI,
               "The last explicitly saved Provider was not active")

        try rebuilt.reset(provider: .openAI)
        expect(rebuilt.load(provider: .openAI).model == AIProviderRegistry.manifest(for: .openAI).defaultModel,
               "Explicit reset did not restore the Manifest default")
        expect(rebuilt.load(provider: .kimi) == kimi,
               "Reset leaked into another Provider profile")

        let consentSuite = "AIDataSharingConsentTests-\(UUID().uuidString)"
        let consentDefaults = UserDefaults(suiteName: consentSuite)!
        defer { consentDefaults.removePersistentDomain(forName: consentSuite) }
        let consentStore = AIDataSharingConsentStore(
            defaults: consentDefaults,
            storageKey: "consent-test"
        )
        var consentConfig = AIConfig(
            provider: .openAI,
            baseURL: "HTTPS://User:Secret@API.Example.com/v1/?token=hidden#fragment",
            model: "gpt-test",
            apiKey: "secret"
        )
        expect(!consentStore.hasConsent(for: consentConfig),
               "A new recipient unexpectedly inherited consent")
        let recipient = AIDataSharingRecipient(config: consentConfig)
        expect(!recipient.scopeID.contains("Secret") && !recipient.scopeID.contains("hidden"),
               "Consent scope persisted URL credentials or query data")
        consentStore.grant(for: consentConfig)
        expect(consentStore.hasConsent(for: consentConfig),
               "Granted recipient did not retain consent")

        consentConfig.baseURL = "https://api.example.com/v1"
        expect(consentStore.hasConsent(for: consentConfig),
               "Equivalent normalized endpoint lost consent")
        consentConfig.baseURL = "https://api.example.com/v2"
        expect(!consentStore.hasConsent(for: consentConfig),
               "Changed endpoint path reused old consent")
        consentConfig.baseURL = "https://api.example.com/v1"
        consentConfig.provider = .anthropic
        expect(!consentStore.hasConsent(for: consentConfig),
               "Changed Provider reused old consent")
        consentConfig.provider = .openAI
        consentStore.revoke(for: consentConfig)
        expect(!consentStore.hasConsent(for: consentConfig),
               "Revoked recipient still had consent")
        consentStore.grant(for: consentConfig)
        consentStore.revokeAll()
        expect(!consentStore.hasConsent(for: consentConfig),
               "Revoke-all left a consent scope behind")

        if failures.isEmpty {
            print("AISettingsProfileTests: PASS")
        } else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
    }
}
