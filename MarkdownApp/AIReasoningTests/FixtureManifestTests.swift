import Foundation

private struct FixtureManifest: Decodable {
    let version: Int
    let verifiedAt: String
    let providers: [ProviderEntry]
}

private struct ProviderEntry: Decodable {
    let id: String
    let nativeRoute: String
    let cases: [String: [String]]
    let capabilities: [String: [String]]
}

@main
enum FixtureManifestTests {
    static func main() throws {
        let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let manifestURL = testDirectory.appendingPathComponent("Fixtures/manifest.json")
        let manifest = try JSONDecoder().decode(
            FixtureManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        var failures: [String] = []
        let expectedProviders = Set(["openAI", "anthropic", "gemini", "qwen", "kimi", "glm"])
        let requiredCases = Set(["request", "stream", "source", "error", "image", "file"])

        if manifest.version != 1 { failures.append("Fixture manifest version changed") }
        if manifest.verifiedAt != "2026-08-24" { failures.append("Fixture review date is stale") }
        if Set(manifest.providers.map(\.id)) != expectedProviders {
            failures.append("Fixture manifest does not contain exactly the six native Providers")
        }

        for provider in manifest.providers {
            if provider.nativeRoute.isEmpty || !provider.nativeRoute.hasPrefix("/") {
                failures.append("\(provider.id) has no native route")
            }
            if !requiredCases.isSubset(of: Set(provider.cases.keys)) {
                failures.append("\(provider.id) is missing required fixture cases")
            }
            if provider.capabilities.isEmpty {
                failures.append("\(provider.id) has no declared capability evidence")
            }
            let evidenceByKind = provider.cases.merging(
                provider.capabilities,
                uniquingKeysWith: { current, next in current + next }
            )
            for (kind, evidence) in evidenceByKind {
                if evidence.isEmpty { failures.append("\(provider.id).\(kind) has no evidence") }
                for reference in evidence {
                    validate(
                        reference,
                        provider: provider.id,
                        testDirectory: testDirectory,
                        failures: &failures
                    )
                }
            }
        }

        if failures.isEmpty {
            print("FixtureManifestTests: PASS")
        } else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
    }

    private static func validate(
        _ reference: String,
        provider: String,
        testDirectory: URL,
        failures: inout [String]
    ) {
        let parts = reference.split(separator: "#", maxSplits: 1).map(String.init)
        let fileURL = testDirectory.appendingPathComponent(parts[0])
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            failures.append("\(provider) evidence is missing: \(reference)")
            return
        }
        guard parts.count == 2 else { return }
        guard let source = try? String(contentsOf: fileURL, encoding: .utf8),
              source.contains(parts[1])
        else {
            failures.append("\(provider) evidence token is missing: \(reference)")
            return
        }
    }
}
