//
//  AIWritingSession.swift
//  MarkdownApp
//
//  一次 AI 写作的多轮会话状态机：持有完整消息历史，发起流式请求、累积文本、维护阶段，
//  支持「反问澄清」（模型调用工具→用户答题→回填继续）与「二次精修/重新生成」。
//  纯逻辑（@Observable），UI（AIWritingView）只读它的 phase/text 来渲染（视图轻、逻辑外移）。
//

import Foundation

@Observable
final class AIWritingSession {
    enum Phase: Equatable {
        case idle                          // 尚未开始（填 prompt 阶段）
        case loading                       // 已发起、等首个事件
        case streaming                     // 正在接收正文
        case awaitingAnswer(ClarifyRequest) // 模型反问，等用户答题（工具内容不进正文）
        case done                          // 一轮完成，可接受/继续精修
        case error(String)                 // 出错，附中文文案
    }

    private(set) var phase: Phase = .idle
    /// 本轮 assistant 的实时缓冲：流式中边收边填，仅供正在生成时展示。每轮开头清空。
    private(set) var text: String = ""
    /// 最近一版「已确认的完整内容」——接受时交出的、完成态展示的都是它。
    /// 与 text 分离是为兜底：一轮若没产出正文（空完成/异常），committedText 不被清掉，正确内容不丢。
    private(set) var committedText: String = ""
    /// 流式中途被打断（如断网）但已有部分结果时的原因文案；nil 表示正常完成。
    private(set) var interruptedReason: String?

    private let config: AIConfig
    private let tools: [AITool]
    /// 完整会话历史（system + user + assistant + tool 结果），多轮都往这里追加。
    private var messages: [AIMessage] = []
    /// 正在等待用户回答的那次工具调用（回填 tool_result 时要带上其 id）。
    private var pendingToolCall: AIToolCall?
    private var didCommit = false
    private var task: Task<Void, Never>?

    /// - Parameter tools: 允许的工具（custom 动作传 [ClarifyTool.definition]，其它传 []）。
    init(config: AIConfig, tools: [AITool]) {
        self.config = config
        self.tools = tools
    }

    var hasContent: Bool { !committedText.isEmpty || !text.isEmpty }
    var isStreaming: Bool { phase == .loading || phase == .streaming }
    var isDone: Bool { phase == .done }
    /// 接受/完成态展示用的最终内容：优先已确认全文，仅当其为空时回退到本轮缓冲。
    var finalText: String { committedText.isEmpty ? text : committedText }

    // MARK: - 对外动作

    /// 发起首轮：给定初始消息序列（system + user）。
    func start(messages: [AIMessage]) {
        self.messages = messages
        runTurn()
    }

    /// 用户回答了反问：把答案作为 tool 结果回填，继续生成。
    func answer(_ answer: String) {
        guard let call = pendingToolCall else { return }
        messages.append(.toolResult(callId: call.id, content: answer))
        pendingToolCall = nil
        runTurn()
    }

    /// 生成完成后二次精修：以当前已确认全文为底稿，重建成一次「单轮文档编辑」请求再生成。
    /// 不再往多轮历史里追加一句话——那样会被模型当成聊天追问、只回一句提示覆盖正文。
    /// 底稿（committedText）会被烘焙进请求消息，因此即便本轮出问题，regenerate 也能从同一底稿重跑。
    func refine(_ instruction: String) {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !committedText.isEmpty else { return }
        messages = AIAction.refineMessages(current: committedText, instruction: trimmed)
        runTurn()
    }

    /// 对上一轮结果重新生成：丢掉最后一段 assistant 结果，用相同历史再来一次。
    func regenerate() {
        if messages.last?.role == .assistant { messages.removeLast() }
        runTurn()
    }

    /// 出错后重试当前这一轮：用现有历史再来一次，不重置会话（保住已有的反问/精修上下文）。
    func retry() {
        runTurn()
    }

    /// 停止接收但保留已生成的部分（可接受部分结果）；无内容则回到 idle。
    func stop() {
        cancel()
        if hasContent {
            commitAssistantTurn()
            phase = .done
        } else {
            phase = .idle
        }
    }

    /// 取消并结束底层请求（Task 取消经 AsyncThrowingStream.onTermination 断流）。
    func cancel() {
        task?.cancel()
        task = nil
    }

    // MARK: - 一轮流式

    private func runTurn() {
        cancel()
        text = ""
        interruptedReason = nil
        pendingToolCall = nil
        didCommit = false
        phase = .loading
        let client = AIClientFactory.make(config)
        task = Task { @MainActor in
            do {
                for try await event in client.stream(messages: messages, tools: tools) {
                    if Task.isCancelled { return }
                    switch event {
                    case .text(let delta):
                        if phase == .loading { phase = .streaming }
                        text += delta
                    case .toolCall(let call):
                        handleToolCall(call)
                        return   // 反问：停止本轮，等用户回答
                    }
                }
                if Task.isCancelled { return }
                commitAssistantTurn()
                phase = .done
            } catch is CancellationError {
                // 用户取消，静默
            } catch {
                let message = (error as? AIError)?.errorDescription ?? error.localizedDescription
                // 已生成部分内容（如流式途中断网）：保留内容、标记中断、转 done，可接受或重试；
                // 只有一无所获时才整屏报错。
                if hasContent {
                    interruptedReason = message
                    commitAssistantTurn()
                    phase = .done
                } else {
                    phase = .error(message)
                }
            }
        }
    }

    /// 收到工具调用：只认反问工具并可视化；无法解析则降级（有内容当完成、否则报错）。
    private func handleToolCall(_ call: AIToolCall) {
        guard call.name == ClarifyTool.name,
              let request = ClarifyRequest(argumentsJSON: call.arguments) else {
            if hasContent {
                commitAssistantTurn()
                phase = .done
            } else {
                phase = .error("AI 返回了无法识别的内容，请重试或换种说法。")
            }
            return
        }
        // 记录 assistant 的这次工具调用（含同轮已产出的文本），供回答后回填继续。
        messages.append(.assistant(text: text, toolCalls: [call]))
        pendingToolCall = call
        phase = .awaitingAnswer(request)
    }

    /// 把本轮正文落入历史与快照（每轮仅一次）。
    /// 只有本轮确有产出（text 非空）才更新 committedText，空完成不会覆盖掉上一版正确内容。
    private func commitAssistantTurn() {
        guard !didCommit, !text.isEmpty else { return }
        didCommit = true
        committedText = text
        messages.append(AIMessage(role: .assistant, content: text))
    }
}
