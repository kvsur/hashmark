//
//  AIWritingSession.swift
//  MarkdownApp
//
//  一次 AI 写作的多轮状态机。正文、推理、搜索来源、附件生命周期和 Provider opaque
//  continuation 分开保存；只有 text 事件可以进入 Markdown 正文。
//

import Combine
import Foundation

@MainActor
final class AIWritingSession: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case reasoning
        case streaming
        case awaitingAnswer(ClarifyRequest)
        case done
        case cancelled
        case interrupted(String)
        case error(String)
    }

    // Internal setters let the focused extension files evolve one logical turn while
    // callers still interact through the action methods below.
    @Published var phase: Phase = .idle
    @Published var text = ""
    @Published var reasoningText = ""
    var reasoningBlocks: [AIReasoningBlock] = []
    @Published var committedText = ""
    @Published var interruptedReason: String?
    var attachmentPreparations: [AIAttachmentPreparation] = []
    @Published var searchTimeline = AISearchTimeline()
    var usage: AIUsage?
    var providerContinuations: [AIProviderContinuation] = []
    var generationPhase: AIGenerationPhase?
    var stopReason: AIStreamStopReason?
    @Published var presentationState = AIPresentationState()

    private(set) var config: AIConfig
    private var tools: [AITool]
    private let clientFactory: (AIConfig) throws -> AIClient
    let attachmentOrchestrator = AIAttachmentOrchestrator()
    private let maxNativeSearchContinuations = 5

    var client: AIClient?
    var messages: [AIMessage] = []
    var selectedAttachments: [AIAttachment] = []
    var activeAttachmentReferences: [AIProviderFileReference] = []
    var pendingToolCall: AIToolCall?
    var didCommit = false
    private var task: Task<Void, Never>?
    var deltaCoalescer: AIStreamDeltaCoalescer!

    convenience init(config: AIConfig, tools: [AITool]) {
        self.init(config: config, tools: tools, clientFactory: AIClientFactory.make)
    }

    init(config: AIConfig, tools: [AITool], clientFactory: @escaping (AIConfig) throws -> AIClient) {
        self.config = config
        self.tools = tools
        self.clientFactory = clientFactory
        deltaCoalescer = AIStreamDeltaCoalescer { [weak self] reasoning, answer in
            guard let self else { return }
            self.reasoningText += reasoning
            self.text += answer
        }
    }

    var hasContent: Bool { !committedText.isEmpty || !text.isEmpty }
    var hasReasoning: Bool { !reasoningText.isEmpty }
    var hasAnswer: Bool { !finalText.isEmpty }
    var isStreaming: Bool { presentationState.phase.isActive }
    var isDone: Bool { presentationState.phase.isTerminal }
    var canAccept: Bool { phase == .done && hasAnswer }
    var finalText: String { committedText.isEmpty ? text : committedText }
    var searchState: AISearchState { searchTimeline.state }
    var citations: [AISearchCitation] { searchTimeline.citations }

    // MARK: - 对外动作

    /// 配置页只会覆盖尚未开始的输入阶段。稳定复用 StateObject 身份，避免替换会话对象时
    /// 丢失 SwiftUI 订阅；一旦开始生成，配置更新留给下一次新会话。
    @discardableResult
    func reconfigure(config: AIConfig, tools: [AITool]) -> Bool {
        guard phase == .idle else { return false }
        self.config = config
        self.tools = tools
        client = nil
        return true
    }

    func start(messages: [AIMessage], attachments: [AIAttachment] = []) {
        self.messages = messages
        selectedAttachments = attachments
        runTurn(resetClient: true)
    }

    func answer(_ answer: String) {
        guard let call = pendingToolCall else { return }
        messages.append(.toolResult(callId: call.id, name: call.name, content: answer))
        pendingToolCall = nil
        runTurn()
    }

    func refine(_ instruction: String) {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !committedText.isEmpty else { return }
        messages = AIAction.refineMessages(current: committedText, instruction: trimmed)
        selectedAttachments = []
        runTurn(resetClient: true)
    }

    func regenerate() {
        if messages.last?.role == .assistant { messages.removeLast() }
        runTurn(resetClient: true)
    }

    func retry() {
        // 失败的 Provider continuation 与上传状态都不可复用；消息历史仍保留。
        runTurn(resetClient: true)
    }

    func stop() {
        guard isStreaming else { return }
        deltaCoalescer.flush()
        cancelActiveWork(markCancelled: false, discardPendingDeltas: false)
        presentationState.cancel()
        phase = .cancelled
    }

    func cancel() {
        cancelActiveWork(markCancelled: true)
    }

    /// Backgrounding ends the current non-idempotent request explicitly. A retry is always
    /// a new turn; the partial answer stays visible but never becomes acceptable Markdown.
    func interruptForBackground() {
        guard isStreaming else { return }
        deltaCoalescer.flush()
        cancelActiveWork(markCancelled: false, discardPendingDeltas: false)
        let message = LocalizationController.string(
            "Generation paused because the app moved to the background. Try again when you're ready."
        )
        interruptedReason = message
        presentationState.interrupt(message)
        phase = .interrupted(message)
    }

    private func cancelActiveWork(
        markCancelled: Bool,
        discardPendingDeltas: Bool = true
    ) {
        task?.cancel()
        task = nil
        if discardPendingDeltas { deltaCoalescer.discard() }
        releaseDetachedReferences()
        if markCancelled {
            presentationState.cancel()
            phase = .cancelled
        }
    }

    // MARK: - 一轮流式

    private func runTurn(resetClient: Bool = false) {
        cancelActiveWork(markCancelled: false)
        if resetClient { client = nil }
        resetTurnState()

        task = Task { @MainActor in
            do {
                let client = try sessionClient()
                let adapter = client as? AIProviderAdapter
                var transportMessages = try await prepareAttachments(using: adapter)
                var nativeSearchContinuations = 0

                while true {
                    var pendingSearchContinuations: [AISearchContinuation] = []

                    let requestMessages = SystemPromptContext.injectingCurrentDateTime(
                        into: transportMessages
                    )
                    streamLoop: for try await event in client.stream(
                        messages: requestMessages,
                        tools: tools
                    ) {
                        try Task.checkCancellation()
                        switch event {
                        case .phase(let value):
                            generationPhase = value
                            presentationState.apply(value)
                        case .reasoningDelta(let delta):
                            if phase == .loading { phase = .reasoning }
                            presentationState.receiveReasoning()
                            deltaCoalescer.appendReasoning(delta)
                        case .reasoningBlock(let block):
                            deltaCoalescer.flush()
                            reasoningBlocks.append(block)
                            if reasoningText.isEmpty, !block.visibleText.isEmpty {
                                reasoningText = block.visibleText
                                if phase == .loading { phase = .reasoning }
                                presentationState.receiveReasoning()
                            }
                        case .text(let delta):
                            if phase == .loading || phase == .reasoning { phase = .streaming }
                            presentationState.receiveAnswerText()
                            deltaCoalescer.appendAnswer(delta)
                        case .toolCall(let call):
                            deltaCoalescer.flush()
                            generationPhase = .usingTool
                            presentationState.apply(.usingTool)
                            AIDiagnostics.sessionToolCall(
                                name: call.name,
                                argumentBytes: call.arguments.utf8.count,
                                phase: diagnosticPhaseName,
                                reasoningCharacters: reasoningText.count,
                                textCharacters: text.count
                            )
                            handleToolCall(call)
                            await releaseActiveReferences(using: adapter)
                            return
                        case .search(let searchEvent):
                            presentationState.apply(.searching)
                            searchTimeline.apply(searchEvent)
                            if case .continuationRequired(let value) = searchEvent {
                                guard acceptsNativeSearchContinuation(value) else {
                                    throw AIError.stream("invalid_native_search_continuation")
                                }
                                pendingSearchContinuations.append(value)
                            }
                        case .fileState(let state):
                            applyFileState(state)
                        case .usage(let value):
                            usage = value
                        case .continuation(let value):
                            providerContinuations.append(value)
                        case .stopReason(let value):
                            stopReason = value
                        }
                    }

                    if !pendingSearchContinuations.isEmpty {
                        deltaCoalescer.flush()
                        guard nativeSearchContinuations < maxNativeSearchContinuations else {
                            throw AIError.stream(LocalizationController.string(
                                "Web search did not finish. Try again or turn it off in Settings."
                            ))
                        }
                        nativeSearchContinuations += 1
                        let resolved = try await resolveNativeSearchContinuations(
                            pendingSearchContinuations,
                            using: adapter
                        )
                        transportMessages = prepareNativeSearchContinuations(
                            resolved,
                            transportMessages: transportMessages
                        )
                        continue
                    }

                    try Task.checkCancellation()
                    deltaCoalescer.flush()
                    generationPhase = .finalizing
                    presentationState.finalizing()
                    await Task.yield()
                    completeSearchIfNeeded()
                    if let message = terminalInterruptionMessage() {
                        interruptedReason = message
                        presentationState.interrupt(message)
                        phase = .interrupted(message)
                    } else {
                        commitAssistantTurn()
                        presentationState.complete()
                        phase = .done
                    }
                    await releaseActiveReferences(using: adapter)
                    task = nil
                    return
                }
            } catch is CancellationError {
                await releaseActiveReferences(using: client as? AIProviderAdapter)
            } catch {
                deltaCoalescer.flush()
                await releaseActiveReferences(using: client as? AIProviderAdapter)
                let message = userFacingMessage(for: error)
                if hasContent || hasReasoning {
                    interruptedReason = message
                    presentationState.interrupt(message)
                    phase = .interrupted(message)
                } else {
                    presentationState.fail(message)
                    phase = .error(message)
                }
                task = nil
            }
        }
    }

    private func resetTurnState() {
        deltaCoalescer.discard()
        text = ""
        reasoningText = ""
        reasoningBlocks = []
        committedText = ""
        interruptedReason = nil
        attachmentPreparations = []
        searchTimeline.reset()
        usage = nil
        providerContinuations = []
        generationPhase = .preparingAttachments
        stopReason = nil
        pendingToolCall = nil
        didCommit = false
        phase = .loading
        presentationState.beginTurn(hasAttachments: !selectedAttachments.isEmpty)
    }

    private func sessionClient() throws -> AIClient {
        if let client { return client }
        let created = try clientFactory(config)
        client = created
        return created
    }
}
