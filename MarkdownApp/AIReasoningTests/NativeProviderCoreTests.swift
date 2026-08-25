import Foundation

private var failures: [String] = []

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { failures.append(message) }
}

private func config(
    _ provider: AIProvider,
    baseURL: String? = nil,
    model: String? = nil,
    search: Bool = true
) -> AIConfig {
    let manifest = AIProviderRegistry.manifest(for: provider)
    return AIConfig(
        provider: provider,
        baseURL: baseURL ?? manifest.defaultBaseURL,
        model: model ?? manifest.defaultModel,
        apiKey: "fixture-key",
        preferences: AICapabilityPreferences(webSearchEnabled: search)
    )
}

@main
enum NativeProviderCoreTests {
    static func main() throws {
        expect(AIProvider.allCases == [.openAI, .anthropic, .gemini, .qwen, .kimi, .glm],
               "The native provider set changed")
        expect(Set(AIProviderRegistry.manifests.keys) == Set(AIProvider.allCases),
               "The manifest is not exhaustive")

        let endpoints: [(AIProvider, String)] = [
            (.openAI, "https://api.openai.com/v1/responses"),
            (.anthropic, "https://api.anthropic.com/v1/messages"),
            (.gemini, "https://generativelanguage.googleapis.com/v1beta/interactions"),
            (.qwen, "https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation"),
            (.kimi, "https://api.moonshot.cn/v1/chat/completions"),
            (.glm, "https://open.bigmodel.cn/api/paas/v4/chat/completions")
        ]
        for (provider, expected) in endpoints {
            let resolved = try AIProviderRegistry.resolve(config(provider))
            expect(resolved.provider == provider, "\(provider.rawValue) resolved as another provider")
            expect(resolved.endpointURL.absoluteString == expected,
                   "\(provider.rawValue) endpoint was \(resolved.endpointURL.absoluteString)")
            let expectedReviewDate = [.gemini, .qwen, .kimi, .glm].contains(provider)
                ? "2026-08-25"
                : "2026-08-24"
            expect(resolved.manifest.verifiedAt == expectedReviewDate,
                   "\(provider.rawValue) manifest lost its review date")
        }

        let openAI = try AIProviderRegistry.resolve(config(.openAI))
        expect(openAI.manifest.webSearch == .openAIHostedTool(type: "web_search"),
               "OpenAI is not using Responses web_search")
        let anthropic = try AIProviderRegistry.resolve(config(.anthropic))
        expect(anthropic.manifest.webSearch == .anthropicServerTool(version: "web_search_20260318"),
               "Anthropic tool version changed")
        expect(anthropic.effectiveCapabilities.displayableReasoning ==
               .unavailable(.incompatibleCombination),
               "Anthropic forced search did not expose its thinking conflict")
        let mythos = try AIProviderRegistry.resolve(config(.anthropic, model: "claude-mythos-5"))
        expect(mythos.effectiveCapabilities.webSearch == .unavailable(.modelNotVerified),
               "Anthropic Mythos received unsupported forced Web Search")
        let kimi = try AIProviderRegistry.resolve(config(.kimi))
        expect(kimi.manifest.webSearch == .kimiFormula(
            name: "web_search",
            uri: "moonshot/web-search:latest",
            requiresThinkingDisabled: true
        ), "Kimi search mechanism changed")
        expect(kimi.effectiveCapabilities.displayableReasoning == .unavailable(.incompatibleCombination),
               "Kimi search did not expose its thinking conflict")
        let kimiK3 = try AIProviderRegistry.resolve(config(.kimi, model: "kimi-k3"))
        expect(kimiK3.effectiveCapabilities.imageInput.isEnabled,
               "Kimi K3 lost native visual input")
        expect(kimiK3.effectiveCapabilities.fileExtraction.isEnabled,
               "Kimi K3 lost Provider-level Files extraction")
        expect(kimiK3.effectiveCapabilities.displayableReasoning.isEnabled,
               "Kimi K3 incorrectly inherited the K2 search/thinking conflict")

        let openAISnapshot = try AIProviderRegistry.resolve(config(
            .openAI,
            model: "gpt-5.7-terra-2026-08-25"
        ))
        expect(openAISnapshot.effectiveCapabilities.imageInput.isEnabled,
               "A GPT-5 family snapshot lost its inherited input contract")
        let anthropicSnapshot = try AIProviderRegistry.resolve(config(
            .anthropic,
            model: "claude-sonnet-5-20260825",
            search: false
        ))
        expect(anthropicSnapshot.effectiveCapabilities.imageInput.isEnabled
               && anthropicSnapshot.effectiveCapabilities.inlinePDF.isEnabled,
               "An active Claude snapshot lost Provider-wide visual/PDF input")

        let unknown = try AIProviderRegistry.resolve(config(.openAI, model: "gpt-unverified"))
        expect(unknown.effectiveCapabilities.webSearch == .unavailable(.modelNotVerified),
               "Unknown model received Web Search")
        expect(unknown.effectiveCapabilities.imageInput == .unavailable(.modelNotVerified),
               "Unknown model received image input")

        let gateway = try AIProviderRegistry.resolve(config(
            .qwen,
            baseURL: "https://gateway.example/provider"
        ))
        expect(gateway.provider == .qwen, "Endpoint override changed Provider identity")
        expect(gateway.endpointURL.absoluteString ==
               "https://gateway.example/provider/api/v1/services/aigc/text-generation/generation",
               "Endpoint override did not preserve the Qwen native route")

        let empty = AIConfig.empty
        expect(empty.validationIssues == [.missingBaseURL, .missingModel, .missingAPIKey],
               "Clean-break empty validation changed")

        if failures.isEmpty {
            print("NativeProviderCoreTests: PASS")
        } else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
    }
}
