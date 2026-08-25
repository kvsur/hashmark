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
enum GLMContractTests {
    static func main() throws {
        try testNativeTextRequest()
        try testReasoningEffortMapping()
        try testStandaloneWebSearchContract()
        try testMissingWebSearchEvidenceRejected()
        try testExactVisualRequest()
        try testTextModelRejectsMedia()
        try testNativeStream()
        try testHeartbeatAndOfficialTerminalFrame()
        try testBackToBackDataLinesWithoutSeparators()
        try testFunctionStream()
        try testReasoningContinuationReplay()
        try testUnknownModelSafety()
        try testTypedError()

        if failures.isEmpty {
            print("GLMContractTests: PASS")
        } else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
    }

    private static func configuration(
        model: String = "glm-5.3",
        reasoningEffort: AIReasoningEffort = .low
    ) throws
        -> ResolvedAIProviderConfiguration
    {
        try AIProviderRegistry.resolve(AIConfig(
            provider: .glm,
            baseURL: "https://open.bigmodel.cn",
            model: model,
            apiKey: "fixture-key",
            preferences: AICapabilityPreferences(reasoningEffort: reasoningEffort)
        ))
    }

    private static func testReasoningEffortMapping() throws {
        let request = try GLMRequestBuilder(configuration: configuration(
            reasoningEffort: .low
        )).makeStreamRequest(
            messages: [AIMessage(role: .user, content: "Answer directly.")],
            tools: [],
            webSearchEvidencePreloaded: true
        )
        let body = try JSONSerialization.jsonObject(
            with: request.httpBody ?? Data()
        ) as? [String: Any]
        expect((body?["thinking"] as? [String: Any])?["type"] as? String
               == "enabled",
               "GLM effort adjustment disabled Thinking")
        expect(body?["reasoning_effort"] as? String == "low",
               "GLM Low effort did not reach the request")

        let optionalRequest = try GLMRequestBuilder(configuration: configuration(
            model: "glm-5.2",
            reasoningEffort: .high
        )).makeStreamRequest(
            messages: [AIMessage(role: .user, content: "Answer directly.")],
            tools: [],
            webSearchEvidencePreloaded: true
        )
        let optionalBody = try JSONSerialization.jsonObject(
            with: optionalRequest.httpBody ?? Data()
        ) as? [String: Any]
        expect((optionalBody?["thinking"] as? [String: Any])?["type"] as? String
               == "enabled",
               "GLM optional Thinking was disabled by effort adjustment")
        expect(optionalBody?["reasoning_effort"] == nil,
               "GLM model without verified effort support received the field")
    }

    private static func testNativeTextRequest() throws {
        expect(AIProviderRegistry.manifest(for: .glm).defaultModel == "glm-5.3",
               "GLM default did not advance to GLM-5.3")
        let request = try GLMRequestBuilder(configuration: configuration()).makeStreamRequest(
            messages: [
                AIMessage(role: .system, content: "Be precise."),
                AIMessage(role: .user, content: "Find a source.")
            ],
            tools: [AITool(
                name: "fixture_tool",
                description: "Fixture function",
                parameters: .object(["type": .string("object")])
            )],
            webSearchEvidencePreloaded: true
        )
        expect(request.url?.path == "/api/paas/v4/chat/completions",
               "GLM first-party chat route changed")
        expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-key",
               "GLM Bearer auth changed")
        let actual = try JSONDecoder().decode(JSONValue.self, from: request.httpBody ?? Data())
        if case .object(let body) = actual {
            expect(body["stream_options"] == nil,
                   "GLM request leaked OpenAI stream_options")
        }
        let expected = try JSONDecoder().decode(
            JSONValue.self,
            from: fixture("glm-native-text-request.json")
        )
        expect(actual == expected, "GLM text/search request changed from the native fixture")
    }

    private static func testStandaloneWebSearchContract() throws {
        let config = try configuration()
        let longQuery = String(repeating: "搜索 ", count: 40)
        let query = GLMWebSearchContract.query(in: [
            AIMessage(role: .user, content: "  \(longQuery)\n最新进展  ")
        ])
        expect(query?.count == GLMWebSearchContract.maxQueryCharacters,
               "GLM standalone search query was not normalized to the official limit")

        let request = try GLMWebSearchContract.makeRequest(
            configuration: config,
            query: query ?? "",
            requestID: "request-fixture"
        )
        expect(request.url?.absoluteString == "https://open.bigmodel.cn/api/paas/v4/web_search",
               "GLM standalone Web Search route changed")
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data())
            as? [String: Any]
        expect(body?["search_intent"] as? Bool == false,
               "GLM standalone search no longer bypasses intent gating")
        expect(body?["search_engine"] as? String == "search_pro",
               "GLM standalone search engine changed")
        expect(body?["content_size"] as? String == "high",
               "GLM standalone evidence lost detailed content")

        let data = Data(#"{"request_id":"search-result","search_result":[{"title":"Swift","content":"Current evidence","link":"https://swift.org/","media":"Swift.org","refer":"1","publish_date":"2026-08-25"}]}"#.utf8)
        let evidence = try GLMWebSearchContract.evidence(
            from: data,
            query: "Swift latest",
            fallbackRequestID: "fallback"
        )
        expect(evidence.requestID == "search-result", "GLM search request ID was lost")
        expect(evidence.citations.first?.url.absoluteString == "https://swift.org/",
               "GLM standalone search citation was not mapped")
        let messages = try GLMWebSearchContract.appendingEvidence(
            evidence,
            instruction: "Use verified evidence.",
            to: [AIMessage(role: .user, content: "What is current?")]
        )
        expect(messages.first?.role == .system,
               "GLM search evidence was not injected as app-controlled context")
        expect(messages.first?.content.contains("Current evidence") == true,
               "GLM search evidence content was lost before chat completion")
    }

    private static func testMissingWebSearchEvidenceRejected() throws {
        do {
            _ = try GLMRequestBuilder(configuration: configuration()).makeStreamRequest(
                messages: [AIMessage(role: .user, content: "Search now")],
                tools: []
            )
            failures.append("GLM chat request was sent without standalone search evidence")
        } catch let error as GLMWireError {
            expect(error == .missingWebSearchEvidence,
                   "GLM missing search evidence rejection changed")
        }
    }

    private static func testExactVisualRequest() throws {
        for model in ["glm-5v-turbo", "glm-4.6v", "glm-4.6v-flash"] {
            let visual = try configuration(model: model)
            expect(visual.effectiveCapabilities.imageInput.isEnabled,
                   "\(model) lost image capability")
            expect(visual.effectiveCapabilities.inlinePDF.isEnabled,
                   "\(model) lost file capability")
        }
        expect(AIProviderRegistry.manifest(for: .glm).documentedModelIDs
            .contains("glm-4.6v-flash"),
               "GLM 4.6V Flash is missing from the current model choices")

        let config = try configuration(model: "glm-5v-turbo")
        expect(config.effectiveCapabilities.imageInput.isEnabled,
               "Exact GLM visual model did not receive image capability")
        expect(!config.effectiveCapabilities.webSearch.isEnabled,
               "GLM visual model unexpectedly received text search capability")
        let request = try GLMRequestBuilder(configuration: config).makeStreamRequest(
            messages: [AIMessage(
                role: .user,
                content: "Read the files.",
                attachments: [.pdf(data: Data("%PDF".utf8), name: "manual.pdf")]
            )],
            tools: [],
            uploadedFiles: [GLMUploadedFile(
                id: "file-1",
                url: "https://files.bigmodel.cn/file-1.pdf",
                name: "uploaded.pdf",
                mimeType: "application/pdf",
                purpose: .directInput
            )]
        )
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        expect((body?["thinking"] as? [String: Any])?["type"] as? String == "enabled",
               "GLM visual model lost its documented thinking mode")
        expect(body?["tools"] == nil, "GLM visual model received text-model Web Search")
        let messages = body?["messages"] as? [[String: Any]]
        let content = messages?.first?["content"] as? [[String: Any]]
        let fileURLs = content?.compactMap { block -> String? in
            (block["file_url"] as? [String: Any])?["url"] as? String
        } ?? []
        expect(fileURLs.contains { $0.hasPrefix("data:application/pdf") },
               "GLM inline file block is missing")
        expect(fileURLs.contains("https://files.bigmodel.cn/file-1.pdf"),
               "GLM uploaded file URL is missing")

        let imageRequest = try GLMRequestBuilder(configuration: config).makeStreamRequest(
            messages: [AIMessage(
                role: .user,
                content: "Read the image.",
                attachments: [.image(Data([1, 2, 3]))]
            )],
            tools: []
        )
        let imageBody = try JSONSerialization.jsonObject(
            with: imageRequest.httpBody ?? Data()
        ) as? [String: Any]
        let imageMessages = imageBody?["messages"] as? [[String: Any]]
        let imageContent = imageMessages?.first?["content"] as? [[String: Any]]
        let imageURLs = imageContent?.compactMap { block -> String? in
            (block["image_url"] as? [String: Any])?["url"] as? String
        } ?? []
        expect(imageURLs.contains("AQID"), "GLM documented raw Base64 image block is missing")

        do {
            _ = try GLMRequestBuilder(configuration: config).makeStreamRequest(
                messages: [AIMessage(
                    role: .user,
                    content: "Mix media.",
                    attachments: [
                        .image(Data([1])),
                        .pdf(data: Data("%PDF".utf8), name: "manual.pdf")
                    ]
                )],
                tools: [],
                webSearchEvidencePreloaded: true
            )
            failures.append("GLM accepted mixed image/file modalities")
        } catch let error as GLMWireError {
            expect(error == .unsupportedInput, "GLM mixed-modality rejection changed")
        }
    }

    private static func testTextModelRejectsMedia() throws {
        for model in ["glm-5.3", "glm-5.2"] {
            let config = try configuration(model: model)
            expect(!config.effectiveCapabilities.imageInput.isEnabled,
                   "\(model) incorrectly received image capability")
            expect(!config.effectiveCapabilities.inlinePDF.isEnabled,
                   "\(model) incorrectly received PDF capability")
            do {
                _ = try GLMRequestBuilder(configuration: config).makeStreamRequest(
                    messages: [AIMessage(
                        role: .user,
                        content: "Read this.",
                        attachments: [.image(Data([1]))]
                    )],
                    tools: [],
                    webSearchEvidencePreloaded: true
                )
                failures.append("\(model) accepted visual content")
            } catch let error as GLMWireError {
                expect(error == .unsupportedInput, "GLM text/visual rejection changed")
            }
        }
    }

    private static func testNativeStream() throws {
        let events = try parse("glm-native-stream.sse")
        expect(events.contains(.reasoningDelta("Check sources.")),
               "GLM reasoning_content delta was not mapped")
        let blocks = events.compactMap { event -> AIReasoningBlock? in
            if case .reasoningBlock(let block) = event { return block }
            return nil
        }
        expect(blocks.first?.continuation?.payload == .string("Check sources."),
               "GLM reasoning_content was not retained for continuation")
        let citations = events.compactMap { event -> AISearchCitation? in
            if case .search(.citation(let value)) = event { return value }
            return nil
        }
        expect(citations.count == 1, "GLM web_search sources were duplicated or lost")
        expect(citations.first?.provider == .glm, "GLM citation lost provider ownership")
        expect(citations.first?.marker == "1", "GLM refer marker was not retained")
        expect(events.contains(.text("Swift uses structured concurrency.")),
               "GLM text delta was not mapped")
        expect(events.contains(.usage(AIUsage(inputTokens: 12, outputTokens: 8, totalTokens: 20))),
               "GLM usage was not mapped")
        expect(events.contains(.continuation(AIProviderContinuation(
            provider: .glm,
            kind: "request_id",
            payload: .string("glm-request")
        ))), "GLM request identity was not retained")
        expect(events.contains(.stopReason(.endTurn)), "GLM stop was not mapped")
    }

    private static func testFunctionStream() throws {
        let events = try parse("glm-native-tool-stream.sse")
        expect(events.contains(.toolCall(AIToolCall(
            id: "call-1",
            name: "fixture_tool",
            arguments: "{\"value\":1}"
        ))), "GLM incremental function call was not assembled")
        expect(events.contains(.stopReason(.toolUse)), "GLM function stop was not mapped")
    }

    private static func testHeartbeatAndOfficialTerminalFrame() throws {
        let parser = GLMStreamParser()
        let heartbeat = try parser.receive(line: "data:")
        expect(heartbeat.isEmpty,
               "GLM empty SSE heartbeat was treated as JSON")
        let separator = try parser.receive(line: "")
        expect(separator.isEmpty,
               "GLM empty SSE heartbeat emitted an event")

        let terminal = #"data: {"id":"1","choices":[{"index":0,"finish_reason":"stop","delta":{"role":"assistant","content":""}}],"usage":{"prompt_tokens":8,"completion_tokens":2,"total_tokens":10}}"#
        let events = try parser.receive(line: terminal)
        expect(events.contains(.usage(AIUsage(inputTokens: 8, outputTokens: 2, totalTokens: 10))),
               "GLM official terminal usage was not mapped")
        expect(events.contains(.stopReason(.endTurn)),
               "GLM official terminal frame was not completed")
    }

    private static func testBackToBackDataLinesWithoutSeparators() throws {
        let parser = GLMStreamParser()
        let reasoning = try parser.receive(
            line: #"data: {"id":"1","choices":[{"delta":{"reasoning_content":"Think."},"finish_reason":null}]}"#
        )
        let answer = try parser.receive(
            line: #"data: {"id":"1","choices":[{"delta":{"content":"Hi"},"finish_reason":"stop"}]}"#
        )
        expect(reasoning.contains(.reasoningDelta("Think.")),
               "GLM back-to-back reasoning chunk was buffered indefinitely")
        expect(answer.contains(.text("Hi")),
               "GLM back-to-back answer chunk was concatenated into invalid JSON")
        expect(answer.contains(.stopReason(.endTurn)),
               "GLM back-to-back terminal chunk did not complete")
    }

    private static func testReasoningContinuationReplay() throws {
        let request = try GLMRequestBuilder(configuration: configuration()).makeStreamRequest(
            messages: [.assistant(
                text: "Answer.",
                toolCalls: [],
                reasoningBlocks: [AIReasoningBlock(
                    visibleText: "Visible.",
                    continuation: AIProviderContinuation(
                        provider: .glm,
                        kind: "reasoning_content",
                        payload: .string("Opaque.")
                    )
                )]
            )],
            tools: [],
            webSearchEvidencePreloaded: true
        )
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        let messages = body?["messages"] as? [[String: Any]]
        expect(messages?.first?["reasoning_content"] as? String == "Opaque.",
               "GLM opaque reasoning continuation was not replayed")
    }

    private static func testUnknownModelSafety() throws {
        let config = try configuration(model: "glm-5v-future")
        expect(!config.effectiveCapabilities.imageInput.isEnabled,
               "Broad GLM visual substring matching returned")
        expect(config.usesNativeWebSearch,
               "Unknown GLM model lost the standalone Web Search trial path")
        let request = try GLMRequestBuilder(configuration: config).makeStreamRequest(
            messages: [AIMessage(role: .user, content: "Hello")],
            tools: [],
            webSearchEvidencePreloaded: true
        )
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        expect(body?["thinking"] == nil, "Unknown GLM model received thinking")
        expect(body?["tools"] == nil,
               "Standalone GLM search leaked a tool into the chat request")
    }

    private static func testTypedError() throws {
        let data = Data(#"{"error":{"code":"1214","message":"invalid parameter"}}"#.utf8)
        do {
            _ = try GLMWireChunk(data: data)
            failures.append("GLM error payload was accepted")
        } catch let error as GLMWireError {
            expect(error == .remote(code: "1214", message: "invalid parameter"),
                   "GLM typed error changed")
        }

        let numericCode = Data(
            #"{"error":{"code":1214,"message":"stream_options is invalid"}}"#.utf8
        )
        do {
            _ = try GLMWireChunk(data: numericCode)
            failures.append("GLM numeric error payload was accepted")
        } catch let error as GLMWireError {
            expect(error == .remote(code: "1214", message: "stream_options is invalid"),
                   "GLM numeric error code regressed to invalidEvent")
        }
    }

    private static func parse(_ fixtureName: String) throws -> [AIStreamEvent] {
        let text = String(data: try fixture(fixtureName), encoding: .utf8) ?? ""
        let parser = GLMStreamParser()
        var events: [AIStreamEvent] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            events.append(contentsOf: try parser.receive(line: String(line)))
        }
        events.append(contentsOf: try parser.finish())
        return events
    }
}
