//
//  WebPreviewView.swift
//  MarkdownApp
//
//  用 WKWebView 渲染 Markdown 的底层封装（UIViewRepresentable 桥接）。
//  只负责「把一段 Markdown 文本渲染成 GitHub 风格网页」，不关心它从哪来。
//  资源全部本地打包（marked + github-markdown-css + highlight.js），全程离线。
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

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // 接收模板里 touchstart/touchend 上报的「触点是否在横滚区」。
        // userContentController 会强持有 handler，包一层弱代理避免延长 Coordinator 生命周期。
        configuration.userContentController.add(
            WeakScriptMessageHandler(context.coordinator),
            name: Coordinator.touchScrollableHandlerName
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
        // 记住最新内容；页面还没加载完时先存起来，didFinish 后再渲染。
        context.coordinator.pendingMarkdown = markdown
        if context.coordinator.isLoaded {
            context.coordinator.render(in: webView)
        }
    }

    // MARK: - Coordinator：桥接 WebView 加载状态与内容注入

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let touchScrollableHandlerName = "touchScrollable"

        var isLoaded = false
        var pendingMarkdown: String = ""
        var onExternalLink: ((URL) -> Void)?
        var onHorizontalTouch: ((Bool) -> Void)?

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == Self.touchScrollableHandlerName,
                  let inScroller = message.body as? Bool else { return }
            onHorizontalTouch?(inScroller)
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

        /// 把当前 Markdown 以 JSON 字符串安全传入页面，调用 renderMarkdown()。
        /// 用数组包一层再剥掉外层中括号，避免个别 Foundation 版本不允许顶层裸字符串（fragment）。
        func render(in webView: WKWebView) {
            guard let data = try? JSONEncoder().encode([pendingMarkdown]),
                  let wrapped = String(data: data, encoding: .utf8) else { return }
            let json = String(wrapped.dropFirst().dropLast())   // ["...\n..."] → "...\n..."
            webView.evaluateJavaScript("window.renderMarkdown(\(json));")
        }
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
