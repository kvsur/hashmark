import Foundation

private var failures: [String] = []

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { failures.append(message) }
}

private func context(
    provider: AIProvider = .openAI,
    model: String,
    descriptor: AIModelDescriptor? = nil,
    evidence: [AICapabilityEvidence] = [],
    now: Date = Date(timeIntervalSince1970: 100)
) -> AICapabilityResolutionContext {
    AICapabilityResolutionContext(
        profileID: AIModelCatalogScope.legacyProfileID,
        provider: provider,
        endpoint: AIProviderRegistry.manifest(for: provider).defaultBaseURL,
        model: model,
        descriptor: descriptor,
        evidence: evidence,
        now: now
    )
}

private func evidence(
    provider: AIProvider = .openAI,
    model: String,
    capability: AIModelCapability,
    outcome: AICapabilityEvidenceOutcome,
    endpoint: String = "https://api.openai.com/v1",
    expiresAt: Date = Date(timeIntervalSince1970: 200),
    manifestVersion: String = AIProviderRegistry.manifestContentVersion
) -> AICapabilityEvidence {
    AICapabilityEvidence(
        id: UUID(),
        profileID: AIModelCatalogScope.legacyProfileID,
        provider: provider,
        normalizedEndpoint: AIModelCatalogScope.normalizedEndpoint(endpoint),
        model: model,
        capability: capability,
        outcome: outcome,
        observedAt: Date(timeIntervalSince1970: 90),
        expiresAt: expiresAt,
        manifestVersion: manifestVersion,
        protocolVersion: AIProviderRegistry.protocolEvidenceVersion,
        reasonCode: "fixture"
    )
}

@main
enum CapabilityResolverTests {
    static func main() throws {
        testPrecedenceAndGranularity()
        testRuntimeEvidenceAndInvalidation()
        testBaselineParity()
        testVerificationStore()
        testFailureClassification()

        if failures.isEmpty {
            print("CapabilityResolverTests: PASS")
        } else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
    }

    private static func testPrecedenceAndGranularity() {
        var metadata = AIModelProviderMetadata()
        metadata.capabilitySignals[.imageInput] = false
        metadata.capabilitySignals[.reasoning] = true
        let descriptor = AIModelDescriptor(
            id: "gpt-5.6-terra",
            displayName: nil,
            metadata: metadata,
            lifecycle: .active,
            source: .providerAPI,
            firstSeenAt: Date(timeIntervalSince1970: 80),
            lastSeenAt: Date(timeIntervalSince1970: 80),
            missingCount: 0
        )
        let values = AICapabilityResolver.resolveAll(context(
            model: "gpt-5.6-terra",
            descriptor: descriptor
        ))
        expect(values[.imageInput]?.state == .unsupported
               && values[.imageInput]?.source == .providerMetadata,
               "Provider metadata did not override an exact Manifest rule")
        expect(values[.reasoning]?.state == .supported,
               "Independent reasoning metadata was coupled to image input")
        expect(values[.pdfInput]?.state == .supported
               && values[.pdfInput]?.source == .exactManifest,
               "An unrelated exact capability was lost")

        let mythos = AICapabilityResolver.resolve(
            .nativeWebSearch,
            context: context(provider: .anthropic, model: "claude-mythos-5")
        )
        expect(mythos.state == .unsupported && mythos.source == .exactManifest,
               "Exact unsupported exception did not beat family inference")

        let family = AICapabilityResolver.resolve(
            .imageInput,
            context: context(model: "gpt-5.7-terra-20260825")
        )
        expect(family.state == .supported && family.source == .familyManifest,
               "Manifest family rule did not resolve a new snapshot")
    }

    private static func testRuntimeEvidenceAndInvalidation() {
        let model = "gpt-future"
        let verified = evidence(model: model, capability: .imageInput, outcome: .supported)
        let runtime = AICapabilityResolver.resolve(
            .imageInput,
            context: context(model: model, evidence: [verified])
        )
        expect(runtime.state == .supported && runtime.source == .runtimeVerification,
               "Valid runtime evidence was ignored")

        let inconclusive = evidence(
            model: model,
            capability: .pdfInput,
            outcome: .inconclusive
        )
        let fallback = AICapabilityResolver.resolve(
            .pdfInput,
            context: context(model: model, evidence: [inconclusive])
        )
        expect(fallback.state == .unverified && fallback.source == .conservativeFallback,
               "Inconclusive evidence became a capability claim")

        let expired = evidence(
            model: model,
            capability: .reasoning,
            outcome: .supported,
            expiresAt: Date(timeIntervalSince1970: 99)
        )
        expect(AICapabilityResolver.resolve(
            .reasoning,
            context: context(model: model, evidence: [expired])
        ).state == .unverified, "Expired evidence was reused")

        let search = AICapabilityResolver.resolve(
            .nativeWebSearch,
            context: context(model: model)
        )
        expect(search.state == .unverified && search.trialEligible,
               "Unknown search did not expose trial-eligible semantics")
        expect(!AICapabilityResolver.resolve(
            .imageInput,
            context: context(model: model)
        ).trialEligible, "Unknown attachment capability became trial-eligible")
    }

    private static func testBaselineParity() {
        for provider in AIProvider.allCases {
            let manifest = AIProviderRegistry.manifest(for: provider)
            var config = AIConfig(
                provider: provider,
                baseURL: manifest.defaultBaseURL,
                model: manifest.defaultModel,
                apiKey: "fixture",
                preferences: AICapabilityPreferences(webSearchEnabled: true)
            )
            if provider == .anthropic || provider == .kimi {
                config.preferences.webSearchEnabled = false
            }
            guard let old = try? AIProviderRegistry.resolve(config) else {
                failures.append("Could not resolve baseline \(provider.rawValue)")
                continue
            }
            let decisions = old.capabilityDecisions(
                evidence: [],
                now: Date(timeIntervalSince1970: 100)
            )
            let pairs: [(EffectiveCapability, AIModelCapability)] = [
                (old.effectiveCapabilities.imageInput, .imageInput),
                (old.effectiveCapabilities.inlinePDF, .pdfInput),
                (old.effectiveCapabilities.directFileInput, .genericFileInput),
                (old.effectiveCapabilities.displayableReasoning, .reasoning),
                (old.effectiveCapabilities.webSearch, .nativeWebSearch)
            ]
            for (legacy, capability) in pairs where legacy.isEnabled {
                expect(decisions[capability]?.state == .supported,
                       "\(provider.rawValue) \(capability.rawValue) regressed from the frozen baseline")
            }
        }
    }

    private static func testVerificationStore() {
        let suiteName = "AICapabilityVerificationStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            failures.append("Could not create verification defaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AICapabilityVerificationStore(defaults: defaults)
        let success = store.recordSuccess(
            profileID: AIModelCatalogScope.legacyProfileID,
            provider: .openAI,
            endpoint: "https://api.openai.com/v1/",
            model: "gpt-future",
            capability: .nativeWebSearch,
            observedAt: Date(timeIntervalSince1970: 10)
        )
        expect(success.outcome == .supported, "Success was not recorded")
        let auth = store.recordFailure(
            profileID: AIModelCatalogScope.legacyProfileID,
            provider: .openAI,
            endpoint: "https://api.openai.com/v1",
            model: "gpt-future",
            capability: .nativeWebSearch,
            failure: .authentication,
            observedAt: Date(timeIntervalSince1970: 11)
        )
        expect(auth.outcome == .inconclusive,
               "Authentication failure became unsupported evidence")
        let unsupported = store.recordFailure(
            profileID: AIModelCatalogScope.legacyProfileID,
            provider: .openAI,
            endpoint: "https://api.openai.com/v1",
            model: "gpt-future",
            capability: .imageInput,
            failure: .explicitUnsupported(reasonCode: "unsupported_parameter"),
            observedAt: Date(timeIntervalSince1970: 12)
        )
        expect(unsupported.outcome == .unsupported,
               "Explicit unsupported failure was not retained")
        expect(store.allEvidence(now: Date(timeIntervalSince1970: 13)).count == 3,
               "Versioned evidence did not persist")
        store.invalidate(profileID: AIModelCatalogScope.legacyProfileID)
        expect(store.allEvidence(now: Date(timeIntervalSince1970: 13)).isEmpty,
               "Profile evidence invalidation failed")
    }

    private static func testFailureClassification() {
        expect(AICapabilityFailurePolicy.classifyHTTP(
            status: 400,
            body: "The web_search tool is not supported by this model."
        ) == .explicitUnsupported(reasonCode: "provider_explicitly_unsupported"),
        "An explicit search rejection was not classified as unsupported")
        expect(AICapabilityFailurePolicy.classifyHTTP(
            status: 400,
            body: "Malformed request body"
        ) == .invalidRequest,
        "A generic 400 response became unsupported evidence")
        expect(AICapabilityFailurePolicy.classifyHTTP(status: 401, body: nil) == .authentication,
               "Authentication failure classification changed")
        expect(AICapabilityFailurePolicy.classifyHTTP(status: 503, body: nil) == .server,
               "Server failure classification changed")
    }
}
