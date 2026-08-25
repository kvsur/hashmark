import Foundation

private var failures: [String] = []

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { failures.append(message) }
}

private func fixture(_ name: String) throws -> Data {
    let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
    return try Data(contentsOf: directory.appendingPathComponent(name))
}

private func events(_ name: String, omittingSeparators: Bool = false) throws -> [AIStreamEvent] {
    let text = String(data: try fixture(name), encoding: .utf8) ?? ""
    let parser = GeminiStreamParser()
    var events: [AIStreamEvent] = []
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    for line in lines where !omittingSeparators || !line.isEmpty {
        events.append(contentsOf: try parser.receive(line: String(line)))
    }
    events.append(contentsOf: try parser.finish())
    return events
}

@main
enum GeminiContractTests {
    static func main() throws {
        try testNativeRequest()
        try testReasoningEffortMapping()
        try testCurrentCapabilityContracts()
        try testStatefulContinuation()
        try testSearchStream()
        try testSeparatorlessStream()
        try testFunctionStream()
        try testUnknownModelSafety()
        try testTypedError()

        if failures.isEmpty {
            print("GeminiContractTests: PASS")
        } else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
    }

    private static func configuration(
        model: String = "gemini-3.7-flash",
        reasoningEffort: AIReasoningEffort = .low
    ) throws
        -> ResolvedAIProviderConfiguration
    {
        try AIProviderRegistry.resolve(AIConfig(
            provider: .gemini,
            baseURL: "https://generativelanguage.googleapis.com",
            model: model,
            apiKey: "fixture-key",
            preferences: AICapabilityPreferences(reasoningEffort: reasoningEffort)
        ))
    }

    private static func testReasoningEffortMapping() throws {
        let request = try GeminiRequestBuilder(configuration: configuration(
            reasoningEffort: .maximum
        )).makeStreamRequest(
            messages: [AIMessage(role: .user, content: "Answer directly.")],
            tools: []
        )
        let body = try JSONSerialization.jsonObject(
            with: request.httpBody ?? Data()
        ) as? [String: Any]
        let generation = body?["generation_config"] as? [String: Any]
        expect(generation?["thinking_level"] as? String == "high",
               "Gemini Maximum effort did not map to its strongest level")
    }

    private static func testNativeRequest() throws {
        let request = try GeminiRequestBuilder(configuration: configuration()).makeStreamRequest(
            messages: [
                AIMessage(role: .system, content: "Be precise."),
                AIMessage(
                    role: .user,
                    content: "Read every source.",
                    attachments: [
                        .image(Data([1, 2, 3])),
                        .pdf(data: Data("%PDF".utf8), name: "inline.pdf")
                    ]
                )
            ],
            tools: [AITool(
                name: "fixture_tool",
                description: "Fixture function",
                parameters: .object(["type": .string("object")])
            )],
            uploadedFiles: [GeminiUploadedFile(
                name: "files/file_fixture",
                uri: "https://generativelanguage.googleapis.com/v1beta/files/file_fixture",
                mimeType: "application/pdf",
                purpose: .directInput
            )],
            fileSearchStoreNames: ["fileSearchStores/store_fixture"]
        )
        expect(request.url?.absoluteString ==
               "https://generativelanguage.googleapis.com/v1beta/interactions?alt=sse",
               "Gemini did not use the Interactions SSE endpoint")
        expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "fixture-key",
               "Gemini API key header changed")
        expect(request.value(forHTTPHeaderField: "Authorization") == nil,
               "Gemini request incorrectly uses Bearer auth")
        let actual = try JSONDecoder().decode(JSONValue.self, from: request.httpBody ?? Data())
        let expected = try JSONDecoder().decode(
            JSONValue.self,
            from: fixture("gemini-interactions-request.json")
        )
        expect(actual == expected, "Gemini Interactions request fixture changed")
    }

    private static func testCurrentCapabilityContracts() throws {
        let flashLite = try configuration(model: "gemini-3.1-flash-lite")
        expect(flashLite.effectiveCapabilities.imageInput.isEnabled,
               "Gemini 3.1 Flash-Lite lost image input")
        expect(flashLite.effectiveCapabilities.inlinePDF.isEnabled,
               "Gemini 3.1 Flash-Lite lost PDF input")
        expect(flashLite.effectiveCapabilities.webSearch.isEnabled,
               "Gemini 3.1 Flash-Lite lost Search grounding")
        expect(flashLite.effectiveCapabilities.fileSearch.isEnabled,
               "Gemini 3.1 Flash-Lite lost File Search")

        let legacy = try configuration(model: "gemini-2.5-flash")
        expect(legacy.effectiveCapabilities.imageInput.isEnabled,
               "Gemini 2.5 Flash lost multimodal input")
        expect(!legacy.effectiveCapabilities.fileSearch.isEnabled,
               "Gemini 2.5 Flash incorrectly received File Search")

        let snapshot = try configuration(model: "gemini-3.7-flash-001")
        expect(snapshot.effectiveCapabilities.imageInput.isEnabled
               && snapshot.effectiveCapabilities.webSearch.isEnabled,
               "A verified Gemini family snapshot lost inherited capabilities")

        let sameGeneration = try configuration(model: "gemini-3.8-flash")
        expect(sameGeneration.effectiveCapabilities.imageInput.isEnabled
               && sameGeneration.effectiveCapabilities.webSearch.isEnabled,
               "A new Gemini 3 writing model did not inherit the verified family contract")
        let imageGenerator = try configuration(model: "gemini-3.1-flash-image")
        expect(!imageGenerator.effectiveCapabilities.webSearch.isEnabled
               && !imageGenerator.effectiveCapabilities.imageInput.isEnabled,
               "A Gemini image-generation resource was mistaken for a writing model")

        let manifest = AIProviderRegistry.manifest(for: .gemini)
        expect(!manifest.documentedModelIDs.contains("gemini-2.0-flash"),
               "A shut-down Gemini 2.0 model remains in the dated manifest")
    }

    private static func testStatefulContinuation() throws {
        let request = try GeminiRequestBuilder(configuration: configuration()).makeStreamRequest(
            messages: [.toolResult(callId: "call_fixture", name: "fixture_tool", content: "ok")],
            tools: [],
            previousInteractionID: "interaction_previous"
        )
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        expect(body?["previous_interaction_id"] as? String == "interaction_previous",
               "previous_interaction_id was not preserved")
        let input = body?["input"] as? [String: Any]
        expect(input?["type"] as? String == "function_result",
               "Gemini function result did not use native Interactions input")
        expect(input?["call_id"] as? String == "call_fixture",
               "Gemini function result lost call_id")
    }

    private static func testSearchStream() throws {
        let values = try events("gemini-interactions-search.sse")
        expect(values.contains(.reasoningDelta("Check current sources.")),
               "Gemini thought summary was not mapped")
        let reasoning = values.compactMap { event -> AIReasoningBlock? in
            if case .reasoningBlock(let block) = event { return block }
            return nil
        }
        expect(reasoning.first?.continuation?.provider == .gemini,
               "Gemini thought signature lost provider ownership")
        expect(values.contains(.phase(.searching)), "Gemini Google Search phase is missing")
        let citations = values.compactMap { event -> AISearchCitation? in
            if case .search(.citation(let citation)) = event { return citation }
            return nil
        }
        expect(citations.count == 1, "Gemini grounding citations were duplicated or lost")
        expect(citations.first?.marker == "0:30", "Gemini citation span changed")
        expect(values.contains(.usage(AIUsage(inputTokens: 8, outputTokens: 6, totalTokens: 14))),
               "Gemini usage was not mapped")
        expect(values.contains(.continuation(AIProviderContinuation(
            provider: .gemini,
            kind: "interaction_id",
            payload: .string("interaction_fixture")
        ))), "Gemini interaction continuation was not retained")
    }

    private static func testSeparatorlessStream() throws {
        let values = try events("gemini-interactions-search.sse", omittingSeparators: true)
        expect(values.contains(.stopReason(.endTurn)),
               "Gemini back-to-back data records were concatenated")
    }

    private static func testFunctionStream() throws {
        let values = try events("gemini-interactions-function.sse")
        expect(values.contains(.toolCall(AIToolCall(
            id: "call_fixture",
            name: "ask_clarifying_question",
            arguments: "{\"answer_type\":\"text\",\"question\":\"Audience?\"}"
        ))), "Gemini native function_call was not mapped")
        expect(values.contains(.stopReason(.toolUse)), "Gemini tool turn did not stop as toolUse")
    }

    private static func testUnknownModelSafety() throws {
        let config = try configuration(model: "gemini-unverified")
        let request = try GeminiRequestBuilder(configuration: config).makeStreamRequest(
            messages: [AIMessage(role: .user, content: "Hello")],
            tools: []
        )
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        let tools = body?["tools"] as? [[String: Any]]
        expect(config.usesNativeWebSearch
               && tools?.contains(where: { $0["type"] as? String == "google_search" }) == true,
               "Unknown Gemini model lost the explicit Google Search trial path")
        expect(body?["generation_config"] == nil, "Unknown Gemini model received thinking config")
    }

    private static func testTypedError() throws {
        let data = Data(#"{"event_type":"interaction.failed","error":{"code":"INVALID_ARGUMENT","message":"bad tool"}}"#.utf8)
        let event = try GeminiWireEvent(data: data)
        expect(event == .interactionFailed("bad tool"), "Gemini typed error changed")
    }
}
