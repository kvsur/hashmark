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

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        onWebViewReady?(webView)
        webView.isOpaque = false                       // 透明背景，露出 SwiftUI 底色
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        // 从 bundle 加载模板。FileSystemSynchronized 可能保留 WebPreview 子目录，也可能摊平到根，
        // 两种情况都兜住。
        let bundle = Bundle.main
        guard let templateURL = bundle.url(forResource: "template", withExtension: "html", subdirectory: "WebPreview")
            ?? bundle.url(forResource: "template", withExtension: "html") else {
            return webView
        }
        // 允许读取模板同目录下的 css/js（相对路径引用即在此目录解析）。
        let readAccess = templateURL.deletingLastPathComponent()
        webView.loadFileURL(templateURL, allowingReadAccessTo: readAccess)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // 外观：明暗切换交给 overrideUserInterfaceStyle，css 的 prefers-color-scheme 会自动响应。
        webView.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light

        context.coordinator.onExternalLink = onExternalLink
        // 记住最新内容；页面还没加载完时先存起来，didFinish 后再渲染。
        context.coordinator.pendingMarkdown = markdown
        if context.coordinator.isLoaded {
            context.coordinator.render(in: webView)
        }
    }

    // MARK: - Coordinator：桥接 WebView 加载状态与内容注入

    final class Coordinator: NSObject, WKNavigationDelegate {
        var isLoaded = false
        var pendingMarkdown: String = ""
        var onExternalLink: ((URL) -> Void)?

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
