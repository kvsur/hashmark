//
//  WebPreviewView.swift
//  MarkdownApp
//
//  用 WKWebView 渲染 Markdown 的底层封装（UIViewRepresentable 桥接）。
//  只负责「把一段 Markdown 文本渲染成 GitHub 风格网页」，不关心它从哪来。
//  资源全部本地打包（marked + highlight.js + Mermaid + KaTeX），全程离线。
//
//  类比前端：这相当于一个受控组件——外部传入 markdown，内部把它塞进 iframe 渲染；
//  markdown 变化时重新调用页面里的 renderMarkdown()。
//

import SwiftUI
import WebKit

struct WebPreviewView: UIViewRepresentable {
    /// 待渲染的原始 Markdown 文本。
    let markdown: String
    /// 由 SwiftUI 环境驱动的深浅色，用来切换 WebView 外观（进而切换 css 明暗）。
    let colorScheme: ColorScheme
    /// 点击文档内 http(s) 外链时回调（交由上层用 SFSafariViewController 弹出），不覆盖当前预览。
    var onExternalLink: ((URL) -> Void)? = nil
    /// WebView 创建后回调，供上层拿到实例做「长截图」等命令式操作。
    var onWebViewReady: ((WKWebView) -> Void)? = nil
    /// 触点进入/离开「可横向滚动区」（宽代码块/表格）时回调，供上层避让滑动切换手势。
    var onHorizontalTouch: ((Bool) -> Void)? = nil
    /// Markdown 渲染后的网页内容高度；供 Modal 内的紧凑预览自适应，普通全屏预览可忽略。
    var onContentHeightChange: ((CGFloat) -> Void)? = nil
    /// 预览滚动位置（0...1），供 iPad 并排编辑时与源码区双向同步。
    var onScrollFractionChange: ((CGFloat) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        WebPreviewTemplate.installConfiguration(into: configuration)
        // 接收模板里 touchstart/touchend 上报的「触点是否在横滚区」。
        // userContentController 会强持有 handler，包一层弱代理避免延长 Coordinator 生命周期。
        configuration.userContentController.add(
            WeakScriptMessageHandler(context.coordinator),
            name: Coordinator.touchScrollableHandlerName
        )
        configuration.userContentController.add(
            WeakScriptMessageHandler(context.coordinator),
            name: Coordinator.previewScrollHandlerName
        )
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        onWebViewReady?(webView)
        webView.isOpaque = false                       // 透明背景，露出 SwiftUI 底色
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        // 从 bundle 加载离线模板（与 AI 流式预览共用同一加载器）。
        WebPreviewTemplate.load(into: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // 外观：明暗切换交给 overrideUserInterfaceStyle，css 的 prefers-color-scheme 会自动响应。
        webView.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light

        context.coordinator.onExternalLink = onExternalLink
        context.coordinator.onHorizontalTouch = onHorizontalTouch
        context.coordinator.onContentHeightChange = onContentHeightChange
        context.coordinator.onScrollFractionChange = onScrollFractionChange
        // 记住最新内容；页面还没加载完时先存起来，didFinish 后再渲染。
        context.coordinator.pendingMarkdown = markdown
        if context.coordinator.isLoaded {
            context.coordinator.render(in: webView)
        }
    }

    // MARK: - Coordinator：桥接 WebView 加载状态与内容注入

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let touchScrollableHandlerName = "touchScrollable"
        static let previewScrollHandlerName = "previewScroll"

        var isLoaded = false
        var pendingMarkdown: String = ""
        private var renderGeneration = 0
        var onExternalLink: ((URL) -> Void)?
        var onHorizontalTouch: ((Bool) -> Void)?
        var onContentHeightChange: ((CGFloat) -> Void)?
        var onScrollFractionChange: ((CGFloat) -> Void)?

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            switch message.name {
            case Self.touchScrollableHandlerName:
                guard let inScroller = message.body as? Bool else { return }
                onHorizontalTouch?(inScroller)
            case Self.previewScrollHandlerName:
                guard let fraction = message.body as? Double else { return }
                DispatchQueue.main.async { [weak self] in
                    self?.onScrollFractionChange?(CGFloat(fraction))
                }
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            render(in: webView)
        }

        /// 只拦「用户点击」产生的外链：http(s) 交上层用 Safari 模态打开；
        /// mailto/tel 等交系统处理；本地模板加载与页内锚点跳转（file://）照常放行。
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            switch url.scheme?.lowercased() {
            case "http", "https":
                onExternalLink?(url)
                decisionHandler(.cancel)
            case "mailto", "tel", "sms", "facetime":
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            default:
                decisionHandler(.allow)
            }
        }

        /// 用 callAsyncJavaScript 直接传参，并等待 KaTeX 字体与 Mermaid SVG 完成后再回报高度。
        /// generation 防止快速编辑时较早的异步渲染晚返回、覆盖最新内容的高度。
        func render(in webView: WKWebView) {
            renderGeneration += 1
            let generation = renderGeneration
            let markdown = pendingMarkdown
            Task { @MainActor [weak self, weak webView] in
                guard let self, let webView,
                      let value = try? await webView.callAsyncJavaScript(
                        "return await window.renderMarkdown(markdown);",
                        arguments: ["markdown": markdown],
                        in: nil,
                        contentWorld: .page
                      ),
                      generation == self.renderGeneration,
                      let height = (value as? NSNumber)?.doubleValue else { return }
                // 回调延后到下一主循环，避免在 UIViewRepresentable 更新期间直接改 SwiftUI 状态。
                DispatchQueue.main.async {
                    self.onContentHeightChange?(CGFloat(height))
                }
            }
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: Coordinator.touchScrollableHandlerName)
        controller.removeScriptMessageHandler(forName: Coordinator.previewScrollHandlerName)
    }
}

/// WKUserContentController 会强持有注册的 handler；用弱代理转发，
/// 避免它把 Coordinator 的生命周期绑到 WebView 配置上。
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
