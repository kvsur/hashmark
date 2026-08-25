import Foundation

enum AIPromptLocale {
    static let uiLanguageName = "English"
}

private var failures: [String] = []

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { failures.append(message) }
}

@main
@MainActor
enum PresentationStateTests {
    static func main() async {
        testVisibleLifecycle()
        testReasoningDisclosureOwnership()
        testScrollOwnership()
        await testDeltaCoalescing()

        if failures.isEmpty {
            print("PresentationStateTests: PASS")
        } else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
    }

    private static func testVisibleLifecycle() {
        var state = AIPresentationState()
        expect(state.phase == .idle, "Presentation did not begin idle")
        state.beginTurn(hasAttachments: true)
        expect(state.phase == .preparingAttachments, "Attachment turn skipped preparation")
        state.apply(.uploading)
        state.apply(.connecting)
        state.receiveReasoning()
        expect(state.phase == .thinking, "Visible reasoning did not enter thinking")
        state.apply(.searching)
        expect(state.phase == .searching, "Search did not receive its own visible phase")
        state.apply(.usingTool)
        expect(state.phase == .usingTool, "Tool use did not receive its own visible phase")
        state.receiveAnswerText()
        expect(state.phase == .generating && state.hasStartedAnswer,
               "First answer text did not enter generating")
        state.apply(.thinking)
        expect(state.phase == .generating,
               "Late reasoning pulled the UI away from an answer already in progress")
        state.finalizing()
        state.complete()
        expect(state.phase == .completed && state.phase.isTerminal,
               "Completed lifecycle did not reach a terminal state")

        state.beginTurn(hasAttachments: false)
        state.interrupt("offline")
        state.receiveAnswerText()
        expect(state.phase == .interrupted("offline"),
               "A late delta mutated an interrupted terminal state")
    }

    private static func testReasoningDisclosureOwnership() {
        var disclosure = AIReasoningDisclosureState()
        disclosure.answerStarted()
        expect(!disclosure.isExpanded, "Answer start did not collapse reasoning by default")

        disclosure.beginTurn()
        disclosure.setExpanded(true)
        disclosure.answerStarted()
        expect(disclosure.isExpanded,
               "Automatic collapse overrode the reader's explicit expanded choice")

        disclosure.beginTurn()
        disclosure.setExpanded(false)
        disclosure.answerStarted()
        expect(!disclosure.isExpanded,
               "Automatic transition overrode the reader's explicit collapsed choice")
    }

    private static func testScrollOwnership() {
        var scroll = AIStreamingScrollState()
        scroll.readerPositionChanged(isNearBottom: false)
        expect(!scroll.followsLatest, "Reader scrolling up did not suspend auto-follow")
        scroll.readerPositionChanged(isNearBottom: false)
        expect(!scroll.followsLatest, "Streaming reclaimed scroll ownership")
        scroll.jumpToLatest()
        expect(scroll.followsLatest, "Jump to latest did not restore auto-follow")
    }

    private static func testDeltaCoalescing() async {
        var flushes: [(String, String)] = []
        let coalescer = AIStreamDeltaCoalescer(interval: .milliseconds(20)) {
            flushes.append(($0, $1))
        }
        for _ in 0..<100 {
            coalescer.appendReasoning("r")
            coalescer.appendAnswer("a")
        }
        try? await Task.sleep(for: .milliseconds(35))
        expect(flushes.count == 1, "High-frequency deltas were published more than once per frame")
        expect(flushes.first?.0.count == 100 && flushes.first?.1.count == 100,
               "Coalescing dropped or reordered deltas")

        coalescer.appendAnswer("final")
        coalescer.flush()
        expect(flushes.last?.1 == "final", "Forced terminal flush dropped the final frame")
    }
}
