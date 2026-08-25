//
//  AIStreamingPreview.swift
//  MarkdownApp
//
//  AI 流式预览：把边收边累积的 Markdown 实时渲染进 WebView。
//  性能关键——上层可以每个 delta 都更新 markdown，这里在 Coordinator 里做 ~60ms 节流，
//  把高频更新合帧成一次 evaluateJavaScript(aiRender)，并保证「结束帧」一定渲染。
//  复用与静态预览相同的离线模板（WebPreviewTemplate）。
//
//  滚动跟随：模板默认贴底自动跟随最新内容；用户一旦主动上滑离底就停止跟随，
//  并经 aiScroll 消息把「是否贴底」上报，驱动上层的「跳到最新」按钮显隐。
//  上层通过 scrollToLatestToken 自增来命令「跳到最新」（恢复跟随并滚到底）。
//

import SwiftUI
import WebKit

struct AIStreamingPreview: UIViewRepresentable {
    /// 到目前为止累积的完整 Markdown。
    let markdown: String
    /// 是否已是最终帧（流结束）。最终帧强制渲染并触发语法高亮。
    let isFinal: Bool
    let colorScheme: ColorScheme
    /// 出参：用户当前是否贴底跟随最新（false = 已上滑离底，应显示「跳到最新」按钮）。
    @Binding var isFollowingBottom: Bool
    /// 入参：上层每自增一次即命令「跳到最新」（恢复跟随并滚到底）。
    var scrollToLatestToken: Int

    /// 上报用的消息名；dismantle 时按此移除，避免 handler 泄漏。
    private static let scrollMessage = "aiScroll"

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        WebPreviewTemplate.installConfiguration(into: config)
        // 弱引用中转，避免 userContentController 强持 Coordinator 造成循环。
        config.userContentController.add(
            WeakScriptMessageProxy(context.coordinator), name: Self.scrollMessage
        )
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        WebPreviewTemplate.load(into: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        // 每次刷新指向最新 binding，消息回调据此上报。
        context.coordinator.onAtBottom = { isFollowingBottom = $0 }
        context.coordinator.enqueue(markdown, isFinal: isFinal, in: webView)
        // token 变化即为一次「跳到最新」命令。
        if scrollToLatestToken != context.coordinator.lastScrollToken {
            context.coordinator.lastScrollToken = scrollToLatestToken
            webView.evaluateJavaScript("window.__aiScrollToLatest && window.__aiScrollToLatest();")
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: scrollMessage)
    }

    // MARK: - Coordinator：节流合帧 + 接收滚动上报

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onAtBottom: ((Bool) -> Void)?
        var lastScrollToken = 0

        private var isLoaded = false
        private var pendingText = ""
        private var pendingFinal = false
        private var hasPending = false
        private var lastRenderedText: String?
        private var lastRenderedFinal = false
        private var lastRender = Date.distantPast
        private var scheduled = false
        private let interval: TimeInterval = 0.06
        private weak var webView: WKWebView?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            flush()   // 模板就绪，把加载期间攒下的内容渲染出来
        }

        // 模板上报「是否贴底跟随」；async 到下一循环再改 binding，避开视图更新期改状态的告警。
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "aiScroll", let atBottom = message.body as? Bool else { return }
            DispatchQueue.main.async { [weak self] in self?.onAtBottom?(atBottom) }
        }

        func enqueue(_ text: String, isFinal: Bool, in webView: WKWebView) {
            self.webView = webView
            // 去重：内容与终态都未变则跳过（isFollowingBottom 变化会触发 updateUIView，
            // 但不应据此重渲染同一内容，否则徒增 innerHTML 重排与闪烁）。
            if text == lastRenderedText, isFinal == lastRenderedFinal { return }
            pendingText = text
            pendingFinal = isFinal
            hasPending = true
            guard isLoaded else { return }

            // 结束帧立即渲染，不受节流限制。
            if isFinal { flush(); return }

            let elapsed = Date().timeIntervalSince(lastRender)
            if elapsed >= interval {
                flush()
            } else if !scheduled {
                scheduled = true
                DispatchQueue.main.asyncAfter(deadline: .now() + (interval - elapsed)) { [weak self] in
                    self?.scheduled = false
                    self?.flush()
                }
            }
        }

        private func flush() {
            guard isLoaded, hasPending, let webView else { return }
            hasPending = false
            lastRender = Date()
            lastRenderedText = pendingText
            lastRenderedFinal = pendingFinal

            // 用数组包一层再剥外层中括号，安全传入 JSON 字符串（同 WebPreviewView.render）。
            guard let data = try? JSONEncoder().encode([pendingText]),
                  let wrapped = String(data: data, encoding: .utf8) else { return }
            let json = String(wrapped.dropFirst().dropLast())
            // aiRender 的 Mermaid 最终增强是异步的；末尾返回 true，避免 evaluateJavaScript
            // 尝试把 Promise 桥接回 Swift（渲染任务仍会在页面内继续执行）。
            webView.evaluateJavaScript("window.aiRender(\(json), \(pendingFinal)); true;")
        }
    }
}

/// 弱引用代理：WKUserContentController 会强持 message handler，直接传 Coordinator 会形成
/// webView → configuration → controller → Coordinator → webView 的环。用它中转打断强引用。
private final class WeakScriptMessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
