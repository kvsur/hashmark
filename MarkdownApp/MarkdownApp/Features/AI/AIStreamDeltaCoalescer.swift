//
//  AIStreamDeltaCoalescer.swift
//  MarkdownApp
//
//  Batches high-frequency Provider deltas before publishing observable strings.
//  The final frame is always flushed synchronously by AIWritingSession.
//

import Foundation

@MainActor
final class AIStreamDeltaCoalescer {
    typealias FlushHandler = (_ reasoning: String, _ answer: String) -> Void

    private let interval: Duration
    private let onFlush: FlushHandler
    private var pendingReasoning = ""
    private var pendingAnswer = ""
    private var scheduledFlush: Task<Void, Never>?

    init(
        interval: Duration = .milliseconds(40),
        onFlush: @escaping FlushHandler
    ) {
        self.interval = interval
        self.onFlush = onFlush
    }

    func appendReasoning(_ delta: String) {
        guard !delta.isEmpty else { return }
        pendingReasoning += delta
        scheduleIfNeeded()
    }

    func appendAnswer(_ delta: String) {
        guard !delta.isEmpty else { return }
        pendingAnswer += delta
        scheduleIfNeeded()
    }

    func flush() {
        scheduledFlush?.cancel()
        scheduledFlush = nil
        guard !pendingReasoning.isEmpty || !pendingAnswer.isEmpty else { return }
        let reasoning = pendingReasoning
        let answer = pendingAnswer
        pendingReasoning = ""
        pendingAnswer = ""
        onFlush(reasoning, answer)
    }

    func discard() {
        scheduledFlush?.cancel()
        scheduledFlush = nil
        pendingReasoning = ""
        pendingAnswer = ""
    }

    private func scheduleIfNeeded() {
        guard scheduledFlush == nil else { return }
        scheduledFlush = Task { [weak self, interval] in
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }
}
