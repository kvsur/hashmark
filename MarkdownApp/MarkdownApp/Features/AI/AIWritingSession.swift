//
//  AIWritingSession.swift
//  MarkdownApp
//
//  一次 AI 写作的会话状态机：发起流式请求、累积文本、维护阶段、支持取消/停止。
//  纯逻辑（@Observable），UI（AIWritingView）只读它的 phase/text 来渲染（视图轻、逻辑外移）。
//

import Foundation

@Observable
final class AIWritingSession {
    enum Phase: Equatable {
        case idle          // 尚未开始（填 prompt 阶段）
        case loading       // 已发起、等首个 delta
        case streaming     // 正在接收
        case done          // 完成（含「停止」保留的部分结果）
        case error(String) // 出错，附中文文案
    }

    private(set) var phase: Phase = .idle
    /// 到目前为止累积的完整生成文本。
    private(set) var text: String = ""

    private var task: Task<Void, Never>?
    private let config: AIConfig

    init(config: AIConfig) { self.config = config }

    var hasContent: Bool { !text.isEmpty }
    var isStreaming: Bool { phase == .streaming || phase == .loading }
    var isDone: Bool { phase == .done }

    /// 发起一次流式生成。会先清空上次结果。
    func start(messages: [AIMessage]) {
        cancel()
        text = ""
        phase = .loading
        let client = AIClientFactory.make(config)
        task = Task { @MainActor in
            do {
                for try await delta in client.stream(messages: messages) {
                    if Task.isCancelled { return }
                    if phase == .loading { phase = .streaming }
                    text += delta
                }
                if Task.isCancelled { return }
                phase = .done
            } catch is CancellationError {
                // 用户取消，静默
            } catch {
                phase = .error((error as? AIError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    /// 停止接收但保留已生成的部分（可接受部分结果）；无内容则回到 idle。
    func stop() {
        cancel()
        phase = hasContent ? .done : .idle
    }

    /// 取消并结束底层请求（Task 取消会经 AsyncThrowingStream.onTermination 断流）。
    func cancel() {
        task?.cancel()
        task = nil
    }
}
