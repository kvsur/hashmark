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
enum AnthropicContractTests {
    static func main() throws {
        try testNativeRequest()
        try testReasoningEffortMapping()
        try testThinkingContinuationOrdering()
        try testNativeStream()
        try testSeparatorlessStream()
        try testUnknownModelSafety()
        try testMiniMaxSearchContract()
        try testTypedError()

        if failures.isEmpty {
            print("AnthropicContractTests: PASS")
        } else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
    }

    private static func configuration(
        model: String = "claude-fable-5",
        webSearch: Bool = true,
        reasoningEffort: AIReasoningEffort = .low
    ) throws
        -> ResolvedAIProviderConfiguration
    {
        try AIProviderRegistry.resolve(AIConfig(
            provider: .anthropic,
            baseURL: "https://api.anthropic.com",
            model: model,
            apiKey: "fixture-key",
            preferences: AICapabilityPreferences(
                webSearchEnabled: webSearch,
                reasoningEffort: reasoningEffort
            )
        ))
    }

    private static func testReasoningEffortMapping() throws {
        let manualRequest = try AnthropicRequestBuilder(configuration: configuration(
            model: "claude-sonnet-4-6",
            webSearch: false,
            reasoningEffort: .maximum
        )).makeStreamRequest(
            messages: [AIMessage(role: .user, content: "Answer directly.")],
            tools: []
        )
        let manualBody = try JSONSerialization.jsonObject(
            with: manualRequest.httpBody ?? Data()
        ) as? [String: Any]
        let manualThinking = manualBody?["thinking"] as? [String: Any]
        expect(manualThinking?["type"] as? String == "enabled"
               && manualThinking?["budget_tokens"] as? Int == 32_768,
               "Anthropic manual Maximum effort did not increase its thinking budget")

        let adaptiveRequest = try AnthropicRequestBuilder(configuration: configuration(
            webSearch: false,
            reasoningEffort: .low
        )).makeStreamRequest(
            messages: [AIMessage(role: .user, content: "Answer directly.")],
            tools: []
        )
        let adaptiveBody = try JSONSerialization.jsonObject(
            with: adaptiveRequest.httpBody ?? Data()
        ) as? [String: Any]
        let thinking = adaptiveBody?["thinking"] as? [String: Any]
        let output = adaptiveBody?["output_config"] as? [String: Any]
        expect(thinking?["type"] as? String == "adaptive"
               && thinking?["display"] as? String == "summarized"
               && output?["effort"] as? String == "low",
               "Anthropic adaptive Low effort did not reach the request")
    }

    private static func testNativeRequest() throws {
        let request = try AnthropicRequestBuilder(configuration: configuration()).makeStreamRequest(
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
            uploadedFiles: [AnthropicUploadedFile(
                id: "file_fixture",
                mimeType: "application/pdf",
                purpose: .directInput
            )]
        )
        expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages",
               "Messages endpoint changed")
        expect(request.value(forHTTPHeaderField: "x-api-key") == "fixture-key",
               "Anthropic x-api-key auth changed")
        expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01",
               "Anthropic version header changed")
        expect(request.value(forHTTPHeaderField: "anthropic-beta") == "files-api-2025-04-14",
               "Files beta header is missing")
        let actual = try JSONDecoder().decode(JSONValue.self, from: request.httpBody ?? Data())
        let expected = try JSONDecoder().decode(
            JSONValue.self,
            from: fixture("anthropic-native-request.json")
        )
        expect(actual == expected, "Anthropic request no longer matches the first-party fixture")
    }

    private static func testThinkingContinuationOrdering() throws {
        let continuation = AIProviderContinuation(
            provider: .anthropic,
            kind: "thinking_block",
            payload: .object([
                "type": .string("thinking"),
                "thinking": .string("Check first."),
                "signature": .string("opaque")
            ])
        )
        let request = try AnthropicRequestBuilder(configuration: configuration()).makeStreamRequest(
            messages: [
                .assistant(
                    text: "Calling a tool.",
                    toolCalls: [AIToolCall(id: "toolu_1", name: "fixture", arguments: "{}")],
                    reasoningBlocks: [AIReasoningBlock(
                        visibleText: "Check first.",
                        continuation: continuation
                    )]
                ),
                .toolResult(callId: "toolu_1", content: "ok")
            ],
            tools: []
        )
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        let messages = body?["messages"] as? [[String: Any]]
        let blocks = messages?.first?["content"] as? [[String: Any]]
        expect(blocks?.map { $0["type"] as? String } == ["thinking", "text", "tool_use"],
               "Thinking signature was not replayed before text and tool_use")
    }

    private static func testNativeStream() throws {
        let text = String(data: try fixture("anthropic-native-stream.sse"), encoding: .utf8) ?? ""
        let parser = AnthropicStreamParser()
        var events: [AIStreamEvent] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            events.append(contentsOf: try parser.receive(line: String(line)))
        }
        events.append(contentsOf: try parser.finish())

        expect(events.contains(.reasoningDelta("Check sources.")),
               "Anthropic thinking delta was not mapped")
        let reasoning = events.compactMap { event -> AIReasoningBlock? in
            if case .reasoningBlock(let block) = event { return block }
            return nil
        }
        expect(reasoning.first?.continuation?.payload == .object([
            "type": .string("thinking"),
            "thinking": .string("Check sources."),
            "signature": .string("opaque-signature")
        ]), "Anthropic thinking signature was not retained opaquely")
        expect(events.contains(.phase(.searching)), "Anthropic server search phase is missing")
        let citations = events.compactMap { event -> AISearchCitation? in
            if case .search(.citation(let value)) = event { return value }
            return nil
        }
        expect(citations.count == 1, "Anthropic citations were duplicated or lost")
        expect(citations.first?.provider == .anthropic, "Citation lost Anthropic ownership")
        expect(events.contains(.text("Swift uses structured concurrency.")),
               "Anthropic text delta was not mapped")
        expect(events.contains(.stopReason(.endTurn)), "Anthropic end_turn was not mapped")
    }

    private static func testSeparatorlessStream() throws {
        let text = String(data: try fixture("anthropic-native-stream.sse"), encoding: .utf8) ?? ""
        let parser = AnthropicStreamParser()
        var events: [AIStreamEvent] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false)
            where !line.isEmpty
        {
            events.append(contentsOf: try parser.receive(line: String(line)))
        }
        events.append(contentsOf: try parser.finish())
        expect(events.contains(.text("Swift uses structured concurrency.")),
               "Anthropic back-to-back data records were concatenated")
    }

    private static func testUnknownModelSafety() throws {
        let config = try configuration(model: "claude-unverified")
        expect(!config.effectiveCapabilities.webSearch.isEnabled,
               "Legacy aggregate unexpectedly claimed unknown Anthropic Web Search")
        expect(config.usesNativeWebSearch,
               "Unknown Anthropic model lost the explicit Web Search trial path")
        let request = try AnthropicRequestBuilder(configuration: config).makeStreamRequest(
            messages: [AIMessage(role: .user, content: "Hello")],
            tools: []
        )
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        let tools = body?["tools"] as? [[String: Any]]
        expect(tools?.contains(where: { $0["name"] as? String == "web_search" }) == true,
               "Unknown Anthropic model did not receive the requested trial tool")
        expect(body?["thinking"] == nil, "Unknown Anthropic model received thinking fields")
    }

    private static func testMiniMaxSearchContract() throws {
        let config = try AIProviderRegistry.resolve(AIConfig(
            provider: .anthropic,
            baseURL: "https://api.minimaxi.com/anthropic",
            model: "MiniMax-M3",
            apiKey: "fixture-key",
            preferences: AICapabilityPreferences(webSearchEnabled: true)
        ))
        expect(MiniMaxWebSearchContract.matches(config),
               "MiniMax Anthropic-compatible endpoint was not recognized")
        let searchRequest = try MiniMaxWebSearchContract.makeRequest(
            configuration: config,
            query: "Swift current version"
        )
        expect(searchRequest.url?.absoluteString
               == "https://api.minimaxi.com/v1/coding_plan/search",
               "MiniMax Web Search endpoint was derived incorrectly")
        expect(searchRequest.value(forHTTPHeaderField: "Authorization")
               == "Bearer fixture-key",
               "MiniMax Web Search bearer authentication is missing")
        let searchBody = try JSONSerialization.jsonObject(
            with: searchRequest.httpBody ?? Data()
        ) as? [String: String]
        expect(searchBody?["q"] == "Swift current version",
               "MiniMax Web Search query changed")

        let response = Data(#"{"organic":[{"title":"Swift","link":"https://swift.org/blog/","snippet":"News","date":"2026-08-01"}],"related_searches":[{"query":"Swift releases"}],"base_resp":{"status_code":0,"status_msg":"success"}}"#.utf8)
        let result = try MiniMaxWebSearchContract.decode(response)
        expect(result.citations.count == 1
               && result.citations.first?.url.absoluteString == "https://swift.org/blog/",
               "MiniMax Web Search citations were not mapped")
        let messages = try MiniMaxWebSearchContract.appendingResult(
            result,
            query: "Swift current version",
            to: [AIMessage(role: .user, content: "Swift current version")]
        )
        expect(messages.suffix(2).first?.toolCalls.first?.name == "web_search"
               && messages.last?.toolName == "web_search",
               "MiniMax search result was not appended as an Anthropic tool result")

        let synthesisRequest = try AnthropicRequestBuilder(configuration: config)
            .makeStreamRequest(messages: messages, tools: [])
        let synthesisBody = try JSONSerialization.jsonObject(
            with: synthesisRequest.httpBody ?? Data()
        ) as? [String: Any]
        expect(synthesisBody?["tool_choice"] == nil,
               "MiniMax synthesis request still forced Anthropic hosted Web Search")
        expect(synthesisBody?["tools"] == nil,
               "MiniMax synthesis request still declared Anthropic hosted Web Search")
    }

    private static func testTypedError() throws {
        let data = Data(#"{"type":"error","error":{"type":"invalid_request_error","message":"bad tool"}}"#.utf8)
        do {
            _ = try AnthropicWireEvent(data: data)
            failures.append("Anthropic error event was accepted")
        } catch let error as AnthropicWireError {
            expect(error == .remote(type: "invalid_request_error", message: "bad tool"),
                   "Anthropic typed error changed")
        }
    }
}
