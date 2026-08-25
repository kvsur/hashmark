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

@main
enum QwenContractTests {
    static func main() throws {
        try testNativeTextRequest()
        try testNativeMultimodalRequest()
        try testCurrentModelRoutes()
        try testNativeStream()
        try testSeparatorlessStream()
        try testNativeToolStream()
        try testUnknownModelSafety()
        try testCompatibleRouteRejected()

        if failures.isEmpty {
            print("QwenContractTests: PASS")
        } else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
    }

    private static func configuration(
        model: String = "qwen-plus",
        baseURL: String = "https://dashscope.aliyuncs.com/api/v1"
    ) throws -> ResolvedAIProviderConfiguration {
        try AIProviderRegistry.resolve(AIConfig(
            provider: .qwen,
            baseURL: baseURL,
            model: model,
            apiKey: "fixture-key"
        ))
    }

    private static func testNativeTextRequest() throws {
        let request = try QwenRequestBuilder(configuration: configuration()).makeStreamRequest(
            messages: [
                AIMessage(role: .system, content: "Be precise."),
                AIMessage(role: .user, content: "Find the source.")
            ],
            tools: [AITool(
                name: "fixture_tool",
                description: "Fixture function",
                parameters: .object(["type": .string("object")])
            )]
        )
        expect(
            request.url?.path == "/api/v1/services/aigc/text-generation/generation",
            "Qwen text request left the native DashScope route"
        )
        expect(request.value(forHTTPHeaderField: "X-DashScope-SSE") == "enable",
               "Qwen native SSE header is missing")
        let actual = try JSONDecoder().decode(JSONValue.self, from: request.httpBody ?? Data())
        let expected = try JSONDecoder().decode(
            JSONValue.self,
            from: fixture("qwen-native-text-request.json")
        )
        expect(actual == expected, "Qwen text request changed from the native fixture")
    }

    private static func testNativeMultimodalRequest() throws {
        let request = try QwenRequestBuilder(
            configuration: configuration(model: "qwen3.5-plus")
        ).makeStreamRequest(
            messages: [AIMessage(
                role: .user,
                content: "Read both inputs.",
                attachments: [
                    .image(Data([1, 2, 3])),
                    .pdf(data: Data("%PDF".utf8), name: "inline.pdf")
                ]
            )],
            tools: [],
            uploadedFiles: [
                QwenUploadedFile(
                    id: "file_input",
                    name: "manual.pdf",
                    mimeType: "application/pdf",
                    purpose: .directInput,
                    extractedText: nil
                ),
                QwenUploadedFile(
                    id: "file_extract",
                    name: "notes.txt",
                    mimeType: "text/plain",
                    purpose: .extraction,
                    extractedText: "Extracted notes"
                )
            ]
        )
        expect(
            request.url?.path == "/api/v1/services/aigc/multimodal-generation/generation",
            "Qwen multimodal request did not switch to its native route"
        )
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        let parameters = body?["parameters"] as? [String: Any]
        let search = parameters?["search_options"] as? [String: Any]
        expect(search?["search_strategy"] as? String == "agent",
               "Qwen multimodal search lost agent strategy")
        expect(search?["forced_search"] as? Bool == true,
               "Qwen multimodal search is not forced")
        expect(search?["enable_citation"] == nil,
               "Qwen agent strategy received unsupported citation options")
        let input = body?["input"] as? [String: Any]
        let messages = input?["messages"] as? [[String: Any]]
        let content = messages?.first?["content"] as? [[String: Any]]
        expect(content?.contains { ($0["image"] as? String)?.hasPrefix("data:image/jpeg") == true } == true,
               "Qwen inline image block is missing")
        expect(content?.contains { ($0["file"] as? String) == "file://file_input" } == true,
               "Qwen uploaded file reference is missing")
        expect(content?.contains { ($0["text"] as? String) == "Extracted notes" } == true,
               "Qwen extracted file text is missing")
    }

    private static func testCurrentModelRoutes() throws {
        let manifest = AIProviderRegistry.manifest(for: .qwen)
        expect(manifest.defaultModel == "qwen3.7-plus",
               "Qwen default did not advance to the current balanced model")
        for model in ["qwen3.8-max", "qwen3.7-plus", "qwen3.6-flash"] {
            expect(manifest.documentedModelIDs.contains(model),
                   "Qwen current manifest is missing \(model)")
        }

        let plus = try configuration(model: "qwen3.7-plus")
        expect(plus.effectiveCapabilities.imageInput.isEnabled,
               "Qwen3.7 Plus lost its documented visual input")
        expect(!plus.effectiveCapabilities.inlinePDF.isEnabled,
               "Qwen3.7 Plus received an unverified native PDF contract")
        let plusRequest = try QwenRequestBuilder(configuration: plus).makeStreamRequest(
            messages: [AIMessage(role: .user, content: "Search current facts.")],
            tools: []
        )
        expect(plusRequest.url?.path.hasSuffix("/multimodal-generation/generation") == true,
               "Qwen3.7 Plus did not use its native multimodal route")
        let plusBody = try JSONSerialization.jsonObject(
            with: plusRequest.httpBody ?? Data()
        ) as? [String: Any]
        let plusParameters = plusBody?["parameters"] as? [String: Any]
        let plusSearch = plusParameters?["search_options"] as? [String: Any]
        expect(plusSearch?["search_strategy"] as? String == "agent",
               "Qwen3.7 Plus multimodal Web Search lost its required agent strategy")

        let maxRequest = try QwenRequestBuilder(
            configuration: configuration(model: "qwen3.7-max")
        ).makeStreamRequest(
            messages: [AIMessage(role: .user, content: "Search current facts.")],
            tools: []
        )
        expect(maxRequest.url?.path.hasSuffix("/text-generation/generation") == true,
               "Qwen3.7 Max text model used the multimodal route")
        let maxBody = try JSONSerialization.jsonObject(
            with: maxRequest.httpBody ?? Data()
        ) as? [String: Any]
        let maxParameters = maxBody?["parameters"] as? [String: Any]
        let maxSearch = maxParameters?["search_options"] as? [String: Any]
        expect(maxSearch?["enable_citation"] as? Bool == true,
               "Qwen3.7 Max text search lost citation options")

        let preview = try configuration(model: "qwen3.6-max-preview")
        expect(preview.effectiveCapabilities.displayableReasoning.isEnabled,
               "Qwen3.6 Max Preview lost reasoning")
        expect(!preview.effectiveCapabilities.webSearch.isEnabled,
               "Qwen3.6 Max Preview received undocumented built-in search")

        let snapshotModel = "qwen3.7-plus-2026-08-01"
        let snapshot = try configuration(model: snapshotModel)
        expect(snapshot.effectiveCapabilities.imageInput.isEnabled
               && snapshot.effectiveCapabilities.webSearch.isEnabled,
               "A Qwen3.7 Plus snapshot lost its family capability contract")
        expect(QwenModelContract.route(for: snapshotModel) == .multimodal,
               "A Qwen3.7 Plus snapshot fell back to the text route")
    }

    private static func testNativeStream() throws {
        let events = try parse("qwen-native-stream.sse")
        expect(events.contains(.reasoningDelta("Check sources.")),
               "Qwen reasoning_content was not mapped")
        expect(events.contains(.phase(.searching)), "Qwen search phase is missing")
        let citations = events.compactMap { event -> AISearchCitation? in
            if case .search(.citation(let value)) = event { return value }
            return nil
        }
        expect(citations.count == 1, "Qwen search_info citations were duplicated or lost")
        expect(citations.first?.provider == .qwen, "Qwen citation lost provider ownership")
        expect(events.contains(.text("Swift uses structured concurrency.")),
               "Qwen text output was not mapped")
        expect(events.contains(.usage(AIUsage(inputTokens: 12, outputTokens: 8, totalTokens: 20))),
               "Qwen final usage was not mapped")
        expect(events.contains(.stopReason(.endTurn)), "Qwen stop reason was not mapped")
    }

    private static func testSeparatorlessStream() throws {
        let events = try parse("qwen-native-stream.sse", omittingSeparators: true)
        expect(events.contains(.text("Swift uses structured concurrency.")),
               "Qwen back-to-back data records were concatenated")
    }

    private static func testNativeToolStream() throws {
        let events = try parse("qwen-native-tool-stream.sse")
        expect(events.contains(.toolCall(AIToolCall(
            id: "call_1",
            name: "fixture_tool",
            arguments: "{\"value\":1}"
        ))), "Qwen incremental tool call was not assembled")
        expect(events.contains(.stopReason(.toolUse)), "Qwen tool stop was not mapped")
    }

    private static func testUnknownModelSafety() throws {
        let config = try configuration(model: "qwen-unverified")
        expect(!config.effectiveCapabilities.webSearch.isEnabled,
               "Unknown Qwen model received Web Search")
        let request = try QwenRequestBuilder(configuration: config).makeStreamRequest(
            messages: [AIMessage(role: .user, content: "Hello")],
            tools: []
        )
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        let parameters = body?["parameters"] as? [String: Any]
        expect(parameters?["enable_search"] == nil, "Unknown Qwen model received enable_search")
        expect(parameters?["enable_thinking"] == nil, "Unknown Qwen model received enable_thinking")
    }

    private static func testCompatibleRouteRejected() throws {
        var config = try configuration()
        config = ResolvedAIProviderConfiguration(
            manifest: config.manifest,
            endpointURL: URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!,
            model: config.model,
            apiKey: config.apiKey,
            effectiveCapabilities: config.effectiveCapabilities
        )
        do {
            _ = try QwenRequestBuilder(configuration: config).makeStreamRequest(
                messages: [AIMessage(role: .user, content: "Hello")],
                tools: []
            )
            failures.append("Qwen compatible-mode route was accepted")
        } catch let error as QwenWireError {
            expect(error == .invalidNativeRoute, "Qwen compatible-mode rejection changed")
        }
    }

    private static func parse(
        _ fixtureName: String,
        omittingSeparators: Bool = false
    ) throws -> [AIStreamEvent] {
        let text = String(data: try fixture(fixtureName), encoding: .utf8) ?? ""
        let parser = QwenStreamParser()
        var events: [AIStreamEvent] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines where !omittingSeparators || !line.isEmpty {
            events.append(contentsOf: try parser.receive(line: String(line)))
        }
        events.append(contentsOf: try parser.finish())
        return events
    }
}
