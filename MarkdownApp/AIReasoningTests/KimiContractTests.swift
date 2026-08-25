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
enum KimiContractTests {
    private static let englishWebSearchPolicy =
        "The app has already completed Web Search for this turn. Use the attached web_search result as the source for current information, never claim that internet access is unavailable when it is present, do not request another web_search, and clearly say when the result lacks reliable evidence instead of answering from memory."

    static func main() throws {
        try testNativeSearchRequest()
        try testReasoningEffortMapping()
        try testFormulaContract()
        try testAlwaysOnSearchPolicy()
        testNativeFilesEndpoint()
        try testThinkingContinuationOrdering()
        try testCurrentModelCapabilities()
        try testVisionAndExtraction()
        try testReasoningStream()
        try testSeparatorlessStream()
        try testSearchStream()
        try testUnknownModelSafety()
        try testTypedError()

        if failures.isEmpty {
            print("KimiContractTests: PASS")
        } else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
    }

    private static func configuration(
        model: String = "kimi-k2.6",
        webSearch: Bool = true,
        reasoningEffort: AIReasoningEffort = .low
    ) throws -> ResolvedAIProviderConfiguration {
        try AIProviderRegistry.resolve(AIConfig(
            provider: .kimi,
            baseURL: "https://api.moonshot.cn/v1",
            model: model,
            apiKey: "fixture-key",
            preferences: AICapabilityPreferences(
                webSearchEnabled: webSearch,
                reasoningEffort: reasoningEffort
            )
        ))
    }

    private static func testReasoningEffortMapping() throws {
        let k2Request = try KimiRequestBuilder(configuration: configuration(
            webSearch: false,
            reasoningEffort: .low
        )).makeStreamRequest(
            messages: [AIMessage(role: .user, content: "Answer directly.")],
            tools: []
        )
        let k2Body = try JSONSerialization.jsonObject(
            with: k2Request.httpBody ?? Data()
        ) as? [String: Any]
        expect((k2Body?["thinking"] as? [String: Any])?["type"] as? String
               == "enabled",
               "Kimi K2 effort adjustment disabled Thinking")

        let k3Request = try KimiRequestBuilder(configuration: configuration(
            model: "kimi-k3",
            webSearch: false,
            reasoningEffort: .low
        )).makeStreamRequest(
            messages: [AIMessage(role: .user, content: "Answer directly.")],
            tools: []
        )
        let k3Body = try JSONSerialization.jsonObject(
            with: k3Request.httpBody ?? Data()
        ) as? [String: Any]
        expect(k3Body?["reasoning_effort"] as? String == "low",
               "Kimi K3 Low effort did not reach the request")
    }

    private static let formulaWebSearchTool = JSONValue.object([
        "type": .string("function"),
        "function": .object([
            "name": .string("web_search"),
            "description": .string("Search the web for information"),
            "parameters": .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object([
                        "description": .string("What to search for"),
                        "type": .string("string")
                    ])
                ]),
                "required": .array([.string("query")])
            ])
        ])
    ])

    private static func testNativeSearchRequest() throws {
        let config = try configuration()
        expect(!config.effectiveCapabilities.displayableReasoning.isEnabled,
               "Kimi search did not disable displayable thinking")
        let arguments = try KimiFormulaContract.webSearchArguments(query: "Find a source.")
        let messages = KimiFormulaContract.appendingWebSearchResult(
            to: [
                AIMessage(role: .system, content: "Be precise."),
                AIMessage(role: .user, content: "Find a source.")
            ],
            callID: "formula-1",
            arguments: arguments,
            result: "----MOONSHOT ENCRYPTED BEGIN----fixture----MOONSHOT ENCRYPTED END----"
        )
        let request = try KimiRequestBuilder(configuration: config).makeStreamRequest(
            messages: messages,
            tools: [AITool(
                name: "fixture_tool",
                description: "Fixture function",
                parameters: .object(["type": .string("object")])
            )],
            formulaTools: [formulaWebSearchTool],
            webSearchPolicy: englishWebSearchPolicy
        )
        expect(request.url?.absoluteString == "https://api.moonshot.cn/v1/chat/completions",
               "Kimi first-party chat endpoint changed")
        expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-key",
               "Kimi Bearer auth changed")
        let actual = try JSONDecoder().decode(JSONValue.self, from: request.httpBody ?? Data())
        if case .object(let body) = actual,
           case .array(let messages)? = body["messages"],
           case .object(let policy)? = messages.first,
           case .string(let policyText)? = policy["content"] {
            expect(policyText.contains("already completed Web Search"),
                   "Kimi search policy did not describe the deterministic Formula result")
            expect(policyText.contains("never claim that internet access is unavailable"),
                   "Kimi search policy still permits a false offline response")
        } else {
            failures.append("Kimi web-search policy system message is missing")
        }
        let expected = try JSONDecoder().decode(
            JSONValue.self,
            from: fixture("kimi-native-search-request.json")
        )
        expect(actual == expected, "Kimi request changed from its independent native fixture")
    }

    private static func testFormulaContract() throws {
        let config = try configuration()
        let toolsRequest = KimiFormulaContract.makeToolsRequest(configuration: config)
        expect(
            toolsRequest.url?.absoluteString ==
                "https://api.moonshot.cn/v1/formulas/moonshot/web-search:latest/tools",
            "Kimi Formula tools endpoint changed"
        )
        expect(toolsRequest.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-key",
               "Kimi Formula tools auth changed")

        let toolsData = try JSONEncoder().encode(JSONValue.object([
            "object": .string("list"),
            "tools": .array([formulaWebSearchTool])
        ]))
        let selectedTool = try KimiFormulaContract.webSearchTool(from: toolsData)
        expect(selectedTool == formulaWebSearchTool,
               "Kimi Formula web_search definition was not selected")

        let fiberRequest = try KimiFormulaContract.makeFiberRequest(
            configuration: config,
            name: "web_search",
            arguments: #"{"query":"Unitree latest stock price"}"#
        )
        expect(
            fiberRequest.url?.absoluteString ==
                "https://api.moonshot.cn/v1/formulas/moonshot/web-search:latest/fibers",
            "Kimi Formula fibers endpoint changed"
        )
        let fiberBody = try JSONDecoder().decode(
            JSONValue.self,
            from: fiberRequest.httpBody ?? Data()
        )
        expect(fiberBody == .object([
            "name": .string("web_search"),
            "arguments": .string(#"{"query":"Unitree latest stock price"}"#)
        ]), "Kimi Formula arguments were not passed through verbatim")

        let protectedResult =
            "----MOONSHOT ENCRYPTED BEGIN----fixture----MOONSHOT ENCRYPTED END----"
        let fiberData = try JSONEncoder().encode(JSONValue.object([
            "status": .string("succeeded"),
            "context": .object(["encrypted_output": .string(protectedResult)])
        ]))
        let decodedResult = try KimiFormulaContract.fiberOutput(from: fiberData)
        expect(decodedResult == protectedResult,
               "Kimi Formula protected search result was not preserved verbatim")

        let arguments = try KimiFormulaContract.webSearchArguments(
            query: "宇树科技现在是否上市？"
        )
        let argumentsValue = try JSONDecoder().decode(
            JSONValue.self,
            from: Data(arguments.utf8)
        )
        expect(argumentsValue == .object(["query": .string("宇树科技现在是否上市？")]),
               "Kimi forced search did not preserve the user query")
    }

    private static func testAlwaysOnSearchPolicy() throws {
        let config = try configuration()
        let builder = KimiRequestBuilder(configuration: config)
        for prompt in ["Hello.", "搜索宇树科技最新的股价。", "Schreibe ein Gedicht."] {
            let initialMessages = [AIMessage(role: .user, content: prompt)]
            expect(builder.pendingWebSearchQuery(in: initialMessages) == prompt,
                   "Kimi enabled search did not cover every user turn: \(prompt)")

            let arguments = try KimiFormulaContract.webSearchArguments(query: prompt)
            let searchedMessages = KimiFormulaContract.appendingWebSearchResult(
                to: initialMessages,
                callID: "formula-1",
                arguments: arguments,
                result: "----MOONSHOT ENCRYPTED BEGIN----fixture----MOONSHOT ENCRYPTED END----"
            )
            expect(builder.pendingWebSearchQuery(in: searchedMessages) == nil,
                   "Kimi planned a duplicate search in the same user turn")

            let request = try builder.makeStreamRequest(
                messages: searchedMessages,
                tools: [],
                formulaTools: [formulaWebSearchTool],
                webSearchPolicy: englishWebSearchPolicy
            )
            let body = try JSONSerialization.jsonObject(
                with: request.httpBody ?? Data()
            ) as? [String: Any]
            expect(body?["tool_choice"] as? String == "none",
                   "Kimi synthesis could trigger a duplicate Formula call")
            expect((body?["thinking"] as? [String: Any])?["type"] as? String == "disabled",
                   "Kimi forced search did not disable incompatible thinking")
        }

        let disabledBuilder = KimiRequestBuilder(configuration: try configuration(webSearch: false))
        let disabledMessages = [AIMessage(role: .user, content: "搜索最新股价。")]
        expect(disabledBuilder.pendingWebSearchQuery(in: disabledMessages) == nil,
               "Kimi ignored the explicit Web Search off preference")
    }

    private static func testNativeFilesEndpoint() {
        let chat = URL(string: "https://api.moonshot.cn/v1/chat/completions")!
        expect(
            KimiNativeEndpoints.files(from: chat).absoluteString ==
                "https://api.moonshot.cn/v1/files",
            "Kimi Files endpoint drifted under the chat path"
        )
    }

    private static func testThinkingContinuationOrdering() throws {
        let continuation = AIProviderContinuation(
            provider: .kimi,
            kind: "reasoning_content",
            payload: .string("Opaque reasoning.")
        )
        let request = try KimiRequestBuilder(
            configuration: configuration(webSearch: false)
        ).makeStreamRequest(
            messages: [
                .assistant(
                    text: "Calling search.",
                    toolCalls: [AIToolCall(
                        id: "formula-1",
                        name: "fixture_tool",
                        arguments: "{\"query\":\"Swift\"}"
                    )],
                    reasoningBlocks: [AIReasoningBlock(
                        visibleText: "Visible reasoning.",
                        continuation: continuation
                    )]
                ),
                .toolResult(
                    callId: "formula-1",
                    name: "fixture_tool",
                    content: "{\"query\":\"Swift\"}"
                )
            ],
            tools: []
        )
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        let messages = body?["messages"] as? [[String: Any]]
        expect(messages?.contains {
            ($0["content"] as? String)?.contains("web_search official tool") == true
        } == false, "Kimi disabled-search turn retained the web-search policy")
        expect((body?["thinking"] as? [String: Any])?["type"] as? String == "enabled",
               "Kimi non-search turn did not enable thinking")
        expect(messages?.first?["reasoning_content"] as? String == "Opaque reasoning.",
               "Kimi reasoning_content continuation was not replayed opaquely")
        expect(messages?.last?["name"] == nil,
               "Kimi Formula tool result included a non-contract name field")
    }

    private static func testVisionAndExtraction() throws {
        let request = try KimiRequestBuilder(
            configuration: configuration(webSearch: false)
        ).makeStreamRequest(
            messages: [AIMessage(
                role: .user,
                content: "Read the image and notes.",
                attachments: [.image(Data([1, 2, 3]))]
            )],
            tools: [],
            uploadedFiles: [
                KimiUploadedFile(
                    id: "file-image",
                    name: "large.png",
                    mimeType: "image/png",
                    purpose: .directInput,
                    extractedText: nil
                ),
                KimiUploadedFile(
                    id: "file-doc",
                    name: "manual.pdf",
                    mimeType: "application/pdf",
                    purpose: .extraction,
                    extractedText: "Extracted document"
                )
            ]
        )
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        let messages = body?["messages"] as? [[String: Any]]
        let userMessage = messages?.first { $0["role"] as? String == "user" }
        let content = userMessage?["content"] as? [[String: Any]]
        let URLs = content?.compactMap { block -> String? in
            let image = block["image_url"] as? [String: Any]
            return image?["url"] as? String
        } ?? []
        expect(URLs.contains { $0.hasPrefix("data:image/jpeg") },
               "Kimi inline image was not serialized")
        expect(URLs.contains("ms://file-image"), "Kimi uploaded media ID was not serialized")
        expect(content?.contains { ($0["text"] as? String) == "Extracted document" } == true,
               "Kimi extracted document text was not serialized")
    }

    private static func testCurrentModelCapabilities() throws {
        for model in ["kimi-k2.5", "kimi-k3"] {
            let config = try configuration(model: model, webSearch: false)
            expect(config.effectiveCapabilities.imageInput.isEnabled,
                   "\(model) lost native image input")
            expect(config.effectiveCapabilities.fileExtraction.isEnabled,
                   "\(model) lost Files content extraction")
            expect(config.effectiveCapabilities.inlinePDF.isEnabled,
                   "\(model) lost PDF attachment acceptance")

            let request = try KimiRequestBuilder(configuration: config).makeStreamRequest(
                messages: [AIMessage(
                    role: .user,
                    content: "Read both inputs.",
                    attachments: [.image(Data([1, 2, 3]))]
                )],
                tools: [],
                uploadedFiles: [KimiUploadedFile(
                    id: "file-doc-\(model)",
                    name: "notes.pdf",
                    mimeType: "application/pdf",
                    purpose: .extraction,
                    extractedText: "Extracted for \(model)"
                )]
            )
            let body = try JSONSerialization.jsonObject(
                with: request.httpBody ?? Data()
            ) as? [String: Any]
            let messages = body?["messages"] as? [[String: Any]]
            let content = messages?.first?["content"] as? [[String: Any]]
            expect(content?.contains {
                (($0["image_url"] as? [String: Any])?["url"] as? String)?
                    .hasPrefix("data:image/jpeg") == true
            } == true, "\(model) image was not serialized")
            expect(content?.contains {
                ($0["text"] as? String) == "Extracted for \(model)"
            } == true, "\(model) extracted attachment was not serialized")

            if model == "kimi-k3" {
                expect(body?["reasoning_effort"] as? String == "low",
                       "Kimi K3 did not use the default Low reasoning_effort")
                expect(body?["thinking"] == nil,
                       "Kimi K3 received the incompatible K2 thinking field")
            } else {
                expect((body?["thinking"] as? [String: Any])?["type"] as? String == "enabled",
                       "Kimi K2.5 lost its thinking toggle")
                expect(body?["reasoning_effort"] == nil,
                       "Kimi K2.5 received the K3 reasoning field")
            }
        }
    }

    private static func testReasoningStream() throws {
        let events = try parse("kimi-native-reasoning-stream.sse")
        expect(events.contains(.reasoningDelta("Check first.")),
               "Kimi reasoning_content delta was not mapped")
        let blocks = events.compactMap { event -> AIReasoningBlock? in
            if case .reasoningBlock(let block) = event { return block }
            return nil
        }
        expect(blocks.first?.continuation?.payload == .string("Check first."),
               "Kimi reasoning_content was not preserved for continuation")
        expect(events.contains(.text("Final answer.")), "Kimi text delta was not mapped")
        expect(events.contains(.usage(AIUsage(inputTokens: 10, outputTokens: 5, totalTokens: 15))),
               "Kimi usage was not mapped")
        expect(events.contains(.stopReason(.endTurn)), "Kimi stop was not mapped")
    }

    private static func testSeparatorlessStream() throws {
        let events = try parse("kimi-native-reasoning-stream.sse", omittingSeparators: true)
        expect(events.contains(.text("Final answer.")),
               "Kimi back-to-back data records were concatenated")
        expect(events.contains(.stopReason(.endTurn)),
               "Kimi separatorless terminal record did not complete")
    }

    private static func testSearchStream() throws {
        do {
            _ = try parse("kimi-native-search-stream.sse")
            failures.append("Kimi accepted a model-driven search continuation after preflight")
        } catch let error as KimiWireError {
            expect(error == .unexpectedFormulaToolCall,
                   "Kimi unexpected Formula call rejection changed")
        }
    }

    private static func testUnknownModelSafety() throws {
        let config = try configuration(model: "kimi-unverified", webSearch: false)
        let request = try KimiRequestBuilder(configuration: config).makeStreamRequest(
            messages: [AIMessage(role: .user, content: "Hello")],
            tools: []
        )
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        expect(body?["thinking"] == nil, "Unknown Kimi model received thinking fields")
        expect(body?["tools"] == nil, "Unknown Kimi model received builtin search")
    }

    private static func testTypedError() throws {
        let data = Data(#"{"error":{"type":"invalid_request_error","message":"bad tool"}}"#.utf8)
        do {
            _ = try KimiWireChunk(data: data)
            failures.append("Kimi error payload was accepted")
        } catch let error as KimiWireError {
            expect(error == .remote(type: "invalid_request_error", message: "bad tool"),
                   "Kimi typed error changed")
        }
    }

    private static func parse(
        _ fixtureName: String,
        omittingSeparators: Bool = false
    ) throws -> [AIStreamEvent] {
        let text = String(data: try fixture(fixtureName), encoding: .utf8) ?? ""
        let parser = KimiStreamParser()
        var events: [AIStreamEvent] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines where !omittingSeparators || !line.isEmpty {
            events.append(contentsOf: try parser.receive(line: String(line)))
        }
        events.append(contentsOf: try parser.finish())
        return events
    }
}
