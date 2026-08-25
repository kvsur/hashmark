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

private func parsedEvents(
    _ name: String,
    omittingSeparators: Bool = false
) throws -> [AIStreamEvent] {
    guard let text = String(data: try fixture(name), encoding: .utf8) else {
        throw OpenAIResponsesWireError.invalidEvent
    }
    let parser = OpenAIResponsesStreamParser()
    var events: [AIStreamEvent] = []
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    for line in lines where !omittingSeparators || !line.isEmpty {
        events.append(contentsOf: try parser.receive(line: String(line)))
    }
    events.append(contentsOf: try parser.finish())
    return events
}

@main
enum OpenAIResponsesContractTests {
    static func main() throws {
        try testNativeRequest()
        try testReasoningEffortMapping()
        try testPreviousResponseContinuation()
        try testTextReasoningStream()
        try testSeparatorlessStream()
        try testFunctionStream()
        try testWebSearchStream()
        try testTypedError()

        if failures.isEmpty {
            print("OpenAIResponsesContractTests: PASS")
        } else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
    }

    private static func resolvedConfiguration(
        reasoningEffort: AIReasoningEffort = .low
    ) throws -> ResolvedAIProviderConfiguration {
        try AIProviderRegistry.resolve(AIConfig(
            provider: .openAI,
            baseURL: "https://api.openai.com/v1",
            model: "gpt-5.6-terra",
            apiKey: "fixture-key",
            preferences: AICapabilityPreferences(reasoningEffort: reasoningEffort)
        ))
    }

    private static func testReasoningEffortMapping() throws {
        let request = try OpenAIResponsesRequestBuilder(
            configuration: resolvedConfiguration(reasoningEffort: .low)
        ).makeStreamRequest(
            messages: [AIMessage(role: .user, content: "Answer directly.")],
            instructions: nil,
            tools: [],
            previousResponseID: nil
        )
        let body = try JSONSerialization.jsonObject(
            with: request.httpBody ?? Data()
        ) as? [String: Any]
        let reasoning = body?["reasoning"] as? [String: Any]
        expect(reasoning?["effort"] as? String == "low",
               "OpenAI Low effort did not reach the request")
        expect(reasoning?["generate_summary"] as? String == "auto",
               "OpenAI effort adjustment disabled its reasoning summary")
    }

    private static func testNativeRequest() throws {
        let config = try resolvedConfiguration()
        let messages = [
            AIMessage(role: .system, content: "Be precise."),
            AIMessage(
                role: .user,
                content: "Use the attached sources.",
                attachments: [
                    .image(Data([1, 2, 3])),
                    .pdf(data: Data("%PDF".utf8), name: "sample.pdf")
                ]
            )
        ]
        let tool = AITool(
            name: "fixture_tool",
            description: "Fixture function",
            parameters: .object(["type": .string("object")])
        )
        let request = try OpenAIResponsesRequestBuilder(configuration: config).makeStreamRequest(
            messages: messages,
            instructions: "Be precise.",
            tools: [tool],
            previousResponseID: nil,
            uploadedFileIDs: ["file_fixture"],
            vectorStoreIDs: ["vs_fixture"]
        )
        expect(request.url?.absoluteString == "https://api.openai.com/v1/responses",
               "Responses endpoint changed")
        expect(request.httpMethod == "POST", "Responses method is not POST")
        expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-key",
               "Responses bearer auth changed")

        let actual = try JSONDecoder().decode(JSONValue.self, from: request.httpBody ?? Data())
        let expected = try JSONDecoder().decode(
            JSONValue.self,
            from: fixture("openai-responses-file-search-request.json")
        )
        expect(actual == expected, "Image/file/web_search/file_search request fixture changed")
    }

    private static func testPreviousResponseContinuation() throws {
        let request = try OpenAIResponsesRequestBuilder(configuration: resolvedConfiguration())
            .makeStreamRequest(
                messages: [.toolResult(
                    callId: "call_fixture",
                    name: "fixture_tool",
                    content: "Developers"
                )],
                instructions: "Be precise.",
                tools: [],
                previousResponseID: "resp_previous"
            )
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        expect(body?["previous_response_id"] as? String == "resp_previous",
               "previous_response_id was not preserved")
        let input = body?["input"] as? [[String: Any]]
        expect(input?.first?["type"] as? String == "function_call_output",
               "Function result did not use Responses input item")
        expect(input?.first?["call_id"] as? String == "call_fixture",
               "Function result lost its call_id")
    }

    private static func testTextReasoningStream() throws {
        let events = try parsedEvents("openai-responses-text-reasoning.sse")
        expect(events.contains(.reasoningDelta("Check the structure.")),
               "Reasoning summary delta was not mapped")
        expect(events.contains(.reasoningBlock(AIReasoningBlock(visibleText: "Check the structure."))),
               "Reasoning summary block was not finalized")
        expect(events.contains(.text("# Native response")), "Text delta was not mapped")
        expect(events.contains(.usage(AIUsage(inputTokens: 12, outputTokens: 8, totalTokens: 20))),
               "Responses usage was not mapped")
        expect(events.contains(.continuation(AIProviderContinuation(
            provider: .openAI,
            kind: "response_id",
            payload: .string("resp_text")
        ))), "Response continuation was not retained")
    }

    private static func testSeparatorlessStream() throws {
        let events = try parsedEvents(
            "openai-responses-text-reasoning.sse",
            omittingSeparators: true
        )
        expect(events.contains(.text("# Native response")),
               "OpenAI back-to-back data records were concatenated")
    }

    private static func testFunctionStream() throws {
        let events = try parsedEvents("openai-responses-function.sse")
        expect(events.contains(.toolCall(AIToolCall(
            id: "call_fixture",
            name: "ask_clarifying_question",
            arguments: "{\"question\":\"Audience?\",\"answer_type\":\"text\"}"
        ))), "Responses function call was not mapped")
        expect(events.contains(.stopReason(.toolUse)), "Function turn stop reason changed")
    }

    private static func testWebSearchStream() throws {
        let events = try parsedEvents("openai-responses-web-search.sse")
        expect(events.contains(.phase(.searching)), "Web Search activity was not exposed")
        let citations = events.compactMap { event -> AISearchCitation? in
            if case .search(.citation(let citation)) = event { return citation }
            return nil
        }
        expect(citations.count == 1, "Web Search sources were duplicated or lost")
        expect(citations.first?.url.absoluteString == "https://swift.org/documentation/",
               "Web Search source URL changed")
        expect(citations.first?.provider == .openAI, "Citation lost OpenAI ownership")
        expect(events.contains(.text("Swift uses structured concurrency.")),
               "Search-backed answer text was not mapped")
    }

    private static func testTypedError() throws {
        let parser = OpenAIResponsesStreamParser()
        do {
            _ = try parser.receive(
                line: #"data: {"type":"response.failed","response":{"id":"resp_failed","status":"failed","error":{"code":"invalid_request_error","message":"bad tool"}}}"#
            )
            failures.append("OpenAI failed response was accepted")
        } catch let error as OpenAIResponsesWireError {
            expect(error == .remote("bad tool"), "OpenAI typed error changed")
        }
    }
}
