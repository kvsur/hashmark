import Foundation

private var failures: [String] = []

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { failures.append(message) }
}

@main
enum ManifestGovernanceTests {
    static func main() throws {
        let manifest = try AIModelManifestLoader.loadDefault()
        expect(manifest.schemaVersion == 1, "Manifest schema version changed")
        expect(Set(manifest.providers.map(\.provider)) == Set(AIProvider.allCases),
               "Manifest does not cover the five Providers")
        expect(manifest.provider(.openAI)?.defaultModel == "gpt-5.6-terra",
               "OpenAI default did not decode from JSON")
        expect(manifest.provider(.gemini)?.supportsWriting(model: "gemini-3.8-flash") == true,
               "Gemini family rule did not decode")
        expect(manifest.provider(.gemini)?.supportsWriting(model: "gemini-3.1-flash-image") == false,
               "Gemini family exclusions were ignored")
        expect(manifest.provider(.anthropic)?.exactState(
            for: .nativeWebSearch,
            model: "claude-mythos-5"
        ) == .unsupported, "Exact unsupported exception was lost")
        expect(manifest.provider(.kimi)?.strategyID(
            key: "reasoningStyle",
            model: "kimi-k3-20260825"
        ) == "kimiReasoningEffort", "Safe family strategy did not decode")

        let invalidVersion = Data(#"{"schemaVersion":99,"contentVersion":"x","protocolEvidenceVersion":"x","providers":[]}"#.utf8)
        do {
            _ = try AIModelManifestLoader.decode(invalidVersion)
            failures.append("Unsupported schema loaded")
        } catch AIModelManifestError.unsupportedSchema(99) {
            // Expected.
        }

        if failures.isEmpty {
            print("ManifestGovernanceTests: PASS")
        } else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
    }
}

