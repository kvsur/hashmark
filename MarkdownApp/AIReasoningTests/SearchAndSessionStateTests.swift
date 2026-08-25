import Foundation

enum AIPromptLocale {
    static var uiLanguageName: String { "English" }
}

nonisolated enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case openAI, anthropic, gemini, kimi, glm
    var id: String { rawValue }
}

nonisolated enum AIModelCapability: Hashable {
    case imageInput, pdfInput, genericFileInput
}

nonisolated struct TestCapability: Equatable {
    let isEnabled: Bool
}

nonisolated struct TestCapabilities: Equatable {
    let imageInput: TestCapability
    let inlinePDF: TestCapability
    let fileExtraction: TestCapability
    let webSearch: TestCapability
}

nonisolated struct TestWebSearch: Equatable {
    let automaticContinuationToolName: String?
}

nonisolated struct TestManifest: Equatable {
    let webSearch: TestWebSearch
}

nonisolated struct ResolvedAIProviderConfiguration: Equatable {
    let provider: AIProvider
    let effectiveCapabilities: TestCapabilities
    let manifest: TestManifest

    var usesNativeWebSearch: Bool {
        effectiveCapabilities.webSearch.isEnabled
    }

    func allowsKnownSafeRequest(_ capability: AIModelCapability) -> Bool {
        switch capability {
        case .imageInput: effectiveCapabilities.imageInput.isEnabled
        case .pdfInput: effectiveCapabilities.inlinePDF.isEnabled
        case .genericFileInput: true
        }
    }
}

nonisolated struct AIConfig {
    let resolvedProvider: ResolvedAIProviderConfiguration?
}

enum LocalizationController {
    @MainActor static func string(_ value: String.LocalizationValue) -> String {
        String(localized: value)
    }
}

nonisolated protocol AIClient {
    func stream(messages: [AIMessage], tools: [AITool]) -> AsyncThrowingStream<AIStreamEvent, Error>
}

nonisolated protocol AIProviderAdapter: AIClient, Sendable {
    var provider: AIProvider { get }
    var configuration: ResolvedAIProviderConfiguration { get }
    func upload(_ request: AIFileUploadRequest) async throws -> AIProviderFileReference
    func delete(_ reference: AIProviderFileReference) async throws
    func resolveNativeSearch(_ continuation: AISearchContinuation) async throws -> String
}

nonisolated enum AIClientFactory {
    static func make(_ config: AIConfig) throws -> AIClient {
        throw AIError.stream("unused")
    }
}

enum AIError: LocalizedError {
    case stream(String)
    case http(status: Int, body: String?)

    var errorDescription: String? {
        switch self {
        case .stream(let message): message
        case .http(let status, _): "HTTP \(status)"
        }
    }
}

nonisolated enum AIDiagnostics {
    static func attachmentPreflight(
        provider: AIProvider,
        attachmentCount: Int,
        totalBytes: Int,
        intents: [String]
    ) {}

    static func sessionToolCall(
        name: String,
        argumentBytes: Int,
        phase: String,
        reasoningCharacters: Int,
        textCharacters: Int
    ) {}

    static func automaticWebSearchContinuation(name: String, turn: Int) {}

    static func unrecognizedTool(name: String, reason: String) {}
}

enum AIAction {
    static func refineMessages(current: String, instruction: String) -> [AIMessage] {
        [
            AIMessage(role: .system, content: "refine"),
            AIMessage(role: .user, content: current + "\n" + instruction)
        ]
    }
}

private struct Script {
    let events: [AIStreamEvent]
    let terminalError: AIError?
    let delay: Duration

    init(
        _ events: [AIStreamEvent],
        terminalError: AIError? = nil,
        delay: Duration = .zero
    ) {
        self.events = events
        self.terminalError = terminalError
        self.delay = delay
    }
}

private final class ScriptedClient: AIClient, @unchecked Sendable {
    private let lock = NSLock()
    private var scripts: [Script]
    private var messageSnapshots: [[AIMessage]] = []

    init(_ scripts: [Script]) {
        self.scripts = scripts
    }

    func stream(
        messages: [AIMessage],
        tools: [AITool]
    ) -> AsyncThrowingStream<AIStreamEvent, Error> {
        lock.lock()
        messageSnapshots.append(messages)
        let script = scripts.isEmpty ? Script([]) : scripts.removeFirst()
        lock.unlock()

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for event in script.events {
                        if script.delay != .zero { try await Task.sleep(for: script.delay) }
                        try Task.checkCancellation()
                        continuation.yield(event)
                    }
                    if let error = script.terminalError {
                        continuation.finish(throwing: error)
                    } else {
                        continuation.finish()
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    func snapshots() -> [[AIMessage]] {
        lock.lock()
        defer { lock.unlock() }
        return messageSnapshots
    }
}

private func configuration(_ provider: AIProvider, search: Bool = true) -> AIConfig {
    AIConfig(resolvedProvider: ResolvedAIProviderConfiguration(
        provider: provider,
        effectiveCapabilities: TestCapabilities(
            imageInput: TestCapability(isEnabled: true),
            inlinePDF: TestCapability(isEnabled: true),
            fileExtraction: TestCapability(isEnabled: true),
            webSearch: TestCapability(isEnabled: search)
        ),
        manifest: TestManifest(webSearch: TestWebSearch(
            automaticContinuationToolName: provider == .kimi ? "web_search" : nil
        ))
    ))
}

private var failures: [String] = []

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { failures.append(message) }
}

@main
@MainActor
enum SearchAndSessionStateTests {
    static func main() async {
        testCurrentDateContext()
        testTimeline()
        testWebSearchExecutionGate()
        await testTypedKimiContinuation()
        await testServerContinuationCannotLoop()
        await testUnknownGenericToolCannotLoop()
        await testClarifyAndOpaqueMultiturn()
        await testRetryRegenerateRefineAndStop()
        await testCancellation()
        await testContinuationLimit()

        if failures.isEmpty {
            print("SearchAndSessionStateTests: PASS")
        } else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
    }

    private static func citation(_ provider: AIProvider = .kimi) -> AISearchCitation {
        AISearchCitation(
            id: "\(provider.rawValue)|apple",
            title: "Swift",
            url: URL(string: "https://developer.apple.com/swift/")!,
            publisher: "Apple Developer",
            marker: "12:17",
            provider: provider,
            query: "Swift",
            sourceIdentity: "apple-swift",
            startIndex: 12,
            endIndex: 17
        )
    }

    private static func testCurrentDateContext() {
        let timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
        let now = Date(timeIntervalSince1970: 0)
        let stale = AIMessage(
            role: .system,
            content: "Current local date and time: 2025-01-01 00:00:00"
        )
        let user = AIMessage(role: .user, content: "What is current?")
        let injected = SystemPromptContext.injectingCurrentDateTime(
            into: [stale, user],
            now: now,
            timeZone: timeZone
        )
        expect(injected.first?.content == "Current local date and time: 1970-01-01 08:00:00",
               "Current local date/time was not injected into the live request")
        expect(injected.filter {
            $0.content.hasPrefix("Current local date and time: ")
        }.count == 1, "Current date/time injection was not idempotent")
        expect(injected.last == user, "Date/time injection changed conversation history")
    }

    private static func testTimeline() {
        expect(AISearchSourceValidator.url("not a source") == nil,
               "Malformed relative source URL was accepted")
        expect(AISearchSourceValidator.url("file:///private/document") == nil,
               "Local file URL was accepted as a web citation")
        var timeline = AISearchTimeline()
        timeline.apply(.started(AISearchActivity(provider: .openAI, query: "Swift", requestID: "s1")))
        expect(timeline.state == .searching(provider: .openAI, query: "Swift"),
               "Source-less search did not enter a visible searching state")
        let first = citation(.openAI)
        let duplicate = AISearchCitation(
            id: "different-id",
            title: "Duplicate",
            url: URL(string: "https://example.com/redirect")!,
            publisher: nil,
            marker: nil,
            provider: .openAI,
            sourceIdentity: "apple-swift"
        )
        timeline.apply(.citation(first))
        timeline.apply(.citation(duplicate))
        expect(timeline.citations == [first], "Streaming/final citations were not deduplicated")
        expect(timeline.citations.first?.startIndex == 12,
               "Citation span metadata was lost")
        timeline.apply(.completed(.openAI))
        expect(timeline.state == .completed(provider: .openAI), "Search did not reach completed")
        timeline.reset()
        expect(timeline.state == .idle && timeline.citations.isEmpty,
               "New logical turn retained stale sources")
    }

    private static func testWebSearchExecutionGate() {
        var required = AIWebSearchExecutionGate(isRequired: true)
        expect(required.accepts(.reasoningDelta("Checking.")),
               "Required search rejected reasoning before evidence")
        expect(!required.accepts(.text("Answer from memory")),
               "Required search allowed answer text before execution evidence")
        expect(!required.isSatisfied,
               "Required search completed without execution evidence")
        expect(required.accepts(.search(.started(AISearchActivity(
            provider: .openAI,
            query: "current",
            requestID: "search-1"
        )))), "Required search rejected its execution evidence")
        expect(required.accepts(.text("Search-backed answer")),
               "Required search rejected answer text after execution evidence")
        expect(required.isSatisfied, "Required search did not retain execution evidence")

        var optional = AIWebSearchExecutionGate(isRequired: false)
        expect(optional.accepts(.text("Offline answer")) && optional.isSatisfied,
               "Search-off turn was incorrectly gated")
    }

    private static func testTypedKimiContinuation() async {
        let arguments = #"{"query":"Swift","results":[]}"#
        let continuation = AISearchContinuation(
            provider: .kimi,
            callID: "search-1",
            toolName: "web_search",
            arguments: arguments
        )
        let source = citation()
        let client = ScriptedClient([
            Script([
                .search(.started(AISearchActivity(
                    provider: .kimi,
                    query: "Swift",
                    requestID: "search-1"
                ))),
                .search(.citation(source)),
                .search(.continuationRequired(continuation))
            ]),
            Script([
                .search(.citation(source)),
                .continuation(AIProviderContinuation(
                    provider: .kimi,
                    kind: "response_id",
                    payload: .string("opaque-response")
                )),
                .text("Final answer"),
                .stopReason(.endTurn)
            ])
        ])
        let session = AIWritingSession(
            config: configuration(.kimi),
            tools: [],
            clientFactory: { _ in client }
        )
        session.start(messages: [AIMessage(role: .user, content: "Use search")])
        await waitUntil { session.isDone }

        let snapshots = client.snapshots()
        expect(snapshots.count == 2, "Typed Kimi search did not make exactly one continuation")
        expect(snapshots.allSatisfy { snapshot in
            snapshot.filter {
                $0.content.hasPrefix("Current local date and time: ")
            }.count == 1
        }, "Kimi search requests did not each receive one fresh local date/time context")
        expect(snapshots.last?.suffix(2).map(\.role) == [.assistant, .tool],
               "Kimi native assistant/tool continuity was not preserved")
        expect(snapshots.last?.last?.content == arguments,
               "Kimi opaque search result was not returned verbatim")
        expect(session.finalText == "Final answer", "Search continuation changed final text")
        expect(!session.finalText.contains("developer.apple.com"),
               "Citation contaminated Markdown正文")
        expect(session.citations == [source], "Search citations were duplicated across subturns")
        expect(session.searchState == .completed(provider: .kimi),
               "Kimi search state did not complete")
        expect(session.providerContinuations.count == 1,
               "Provider opaque continuation was not retained separately")
    }

    private static func testServerContinuationCannotLoop() async {
        let client = ScriptedClient([Script([
            .search(.continuationRequired(AISearchContinuation(
                provider: .openAI,
                callID: "server-tool",
                toolName: "web_search",
                arguments: "{}"
            )))
        ])])
        let session = AIWritingSession(
            config: configuration(.openAI),
            tools: [],
            clientFactory: { _ in client }
        )
        session.start(messages: [AIMessage(role: .user, content: "Search")])
        await waitUntil { isError(session.phase) }
        expect(client.snapshots().count == 1,
               "Server-executed search entered a client continuation loop")
    }

    private static func testUnknownGenericToolCannotLoop() async {
        let client = ScriptedClient([Script([
            .toolCall(AIToolCall(id: "legacy", name: "$web_search", arguments: "{}"))
        ])])
        let session = AIWritingSession(
            config: configuration(.kimi),
            tools: [],
            clientFactory: { _ in client }
        )
        session.start(messages: [AIMessage(role: .user, content: "Search")])
        await waitUntil { isError(session.phase) }
        expect(client.snapshots().count == 1,
               "Generic toolCall still triggered automatic web search")
    }

    private static func testClarifyAndOpaqueMultiturn() async {
        let arguments = #"{"question":"Tone?","answer_type":"text"}"#
        let opaque = AIProviderContinuation(
            provider: .anthropic,
            kind: "thinking_block",
            payload: .object(["signature": .string("private")])
        )
        let client = ScriptedClient([
            Script([.toolCall(AIToolCall(
                id: "clarify-1",
                name: ClarifyTool.name,
                arguments: arguments
            ))]),
            Script([
                .reasoningBlock(AIReasoningBlock(
                    visibleText: "Plan",
                    continuation: opaque
                )),
                .text("Polished answer"),
                .stopReason(.endTurn)
            ])
        ])
        let session = AIWritingSession(
            config: configuration(.anthropic),
            tools: [ClarifyTool.definition],
            clientFactory: { _ in client }
        )
        session.start(messages: [AIMessage(role: .user, content: "Write")])
        await waitUntil {
            if case .awaitingAnswer = session.phase { return true }
            return false
        }
        session.answer("Formal")
        await waitUntil { session.isDone }

        let second = client.snapshots().last
        expect(second?.last?.role == .tool && second?.last?.content == "Formal",
               "Clarify answer did not continue the same logical history")
        expect(session.reasoningText == "Plan" && session.finalText == "Polished answer",
               "Reasoning and text were not isolated in multi-turn state")
        expect(!session.finalText.contains("private"), "Opaque thinking data leaked into正文")
    }

    private static func testRetryRegenerateRefineAndStop() async {
        let client = ScriptedClient([
            Script([], terminalError: .stream("offline")),
            Script([.text("first"), .stopReason(.endTurn)]),
            Script([.text("second"), .stopReason(.endTurn)]),
            Script([.text("third"), .stopReason(.endTurn)]),
            Script([.text("partial"), .text("late")], delay: .milliseconds(60))
        ])
        let session = AIWritingSession(
            config: configuration(.openAI),
            tools: [],
            clientFactory: { _ in client }
        )
        session.start(messages: [AIMessage(role: .user, content: "Write")])
        await waitUntil { isError(session.phase) }
        session.retry()
        await waitUntil { session.isDone && session.finalText == "first" }
        session.regenerate()
        await waitUntil { session.isDone && session.finalText == "second" }
        session.refine("Shorter")
        await waitUntil { session.isDone && session.finalText == "third" }

        session.start(messages: [AIMessage(role: .user, content: "Stop")])
        await waitUntil { session.text == "partial" }
        session.stop()
        expect(session.isDone && session.finalText == "partial",
               "Stop did not preserve the partial text")
        let snapshots = client.snapshots()
        expect(snapshots.count == 5, "Retry/regenerate/refine/stop made an unexpected request count")
        expect(snapshots[2].last?.role == .user,
               "Regenerate resent the previous assistant output")
        expect(snapshots[3].last?.content.contains("Shorter") == true,
               "Refine did not rebuild from the committed draft")
    }

    private static func testContinuationLimit() async {
        let scripts = (0..<6).map { index in
            Script([.search(.continuationRequired(AISearchContinuation(
                provider: .kimi,
                callID: "loop-\(index)",
                toolName: "web_search",
                arguments: #"{"query":"loop"}"#
            )))])
        }
        let client = ScriptedClient(scripts)
        let session = AIWritingSession(
            config: configuration(.kimi),
            tools: [],
            clientFactory: { _ in client }
        )
        session.start(messages: [AIMessage(role: .user, content: "Loop")])
        await waitUntil { isError(session.phase) }
        expect(client.snapshots().count == 6, "Native search loop bound changed")
    }

    private static func testCancellation() async {
        let client = ScriptedClient([Script([
            .search(.started(AISearchActivity(provider: .gemini, query: nil, requestID: "cancel"))),
            .text("late")
        ], delay: .milliseconds(80))])
        let session = AIWritingSession(
            config: configuration(.gemini),
            tools: [],
            clientFactory: { _ in client }
        )
        session.start(messages: [AIMessage(role: .user, content: "Cancel")])
        try? await Task.sleep(for: .milliseconds(20))
        session.cancel()
        try? await Task.sleep(for: .milliseconds(120))
        expect(session.text.isEmpty && session.citations.isEmpty,
               "Cancelled stream mutated text or source state afterward")
        expect(client.snapshots().count == 1, "Cancellation restarted the request")
    }

    private static func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool,
        attempts: Int = 300
    ) async {
        for _ in 0..<attempts {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        failures.append("Timed out waiting for session state")
    }

    private static func isError(_ phase: AIWritingSession.Phase) -> Bool {
        if case .error = phase { return true }
        return false
    }
}
