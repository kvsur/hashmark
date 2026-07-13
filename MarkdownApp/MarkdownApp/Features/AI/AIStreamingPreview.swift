//
//  AIStreamingPreview.swift
//  MarkdownApp
//
//  AI 流式预览：把边收边累积的 Markdown 实时渲染进 WebView。
//  性能关键——上层可以每个 delta 都更新 markdown，这里在 Coordinator 里做 ~60ms 节流，
//  把高频更新合帧成一次 evaluateJavaScript(aiRender)，并保证「结束帧」一定渲染。
//  复用与静态预览相同的离线模板（WebPreviewTemplate）。
//

import SwiftUI
import WebKit

struct AIStreamingPreview: UIViewRepresentable {
    /// 到目前为止累积的完整 Markdown。
    let markdown: String
    /// 是否已是最终帧（流结束）。最终帧强制渲染并触发语法高亮。
    let isFinal: Bool
    let colorScheme: ColorScheme

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        WebPreviewTemplate.load(into: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        context.coordinator.enqueue(markdown, isFinal: isFinal, in: webView)
    }

    // MARK: - Coordinator：节流合帧

    final class Coordinator: NSObject, WKNavigationDelegate {
        private var isLoaded = false
        private var pendingText = ""
        private var pendingFinal = false
        private var hasPending = false
        private var lastRender = Date.distantPast
        private var scheduled = false
        private let interval: TimeInterval = 0.06
        private weak var webView: WKWebView?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            flush()   // 模板就绪，把加载期间攒下的内容渲染出来
        }

        func enqueue(_ text: String, isFinal: Bool, in webView: WKWebView) {
            self.webView = webView
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

            // 用数组包一层再剥外层中括号，安全传入 JSON 字符串（同 WebPreviewView.render）。
            guard let data = try? JSONEncoder().encode([pendingText]),
                  let wrapped = String(data: data, encoding: .utf8) else { return }
            let json = String(wrapped.dropFirst().dropLast())
            webView.evaluateJavaScript("window.aiRender(\(json), \(pendingFinal));")
        }
    }
}
