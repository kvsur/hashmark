//
//  WebPreviewTemplate.swift
//  MarkdownApp
//
//  本地渲染模板（marked + css + highlight.js）的加载器。
//  静态预览（WebPreviewView）与 AI 流式预览（AIStreamingPreview）共用（DRY）。
//

import Foundation
import WebKit

enum WebPreviewTemplate {
    /// 把 Web 图表查看器的辅助功能文案注入页面；静态预览与 AI 预览共用，
    /// 并遵循 App 内语言切换，而不是只读取系统语言。
    static func installConfiguration(into configuration: WKWebViewConfiguration) {
        let labels = [
            "open": LocalizationController.string("Open Diagram"),
            "close": LocalizationController.string("Close"),
            "zoomIn": LocalizationController.string("Zoom In"),
            "zoomOut": LocalizationController.string("Zoom Out"),
            "reset": LocalizationController.string("Reset View")
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: labels, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return }
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: "window.__markdownPreviewLabels = \(json);",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
    }

    /// 把 bundle 内的离线模板载入 webView，并授予同目录 css/js 的读取权限。
    /// FileSystemSynchronized 可能保留 WebPreview 子目录，也可能摊平到根，两种都兜住。
    static func load(into webView: WKWebView) {
        let bundle = Bundle.main
        guard let templateURL = bundle.url(
            forResource: "template", withExtension: "html", subdirectory: "WebPreview"
        ) ?? bundle.url(forResource: "template", withExtension: "html") else {
            return
        }
        webView.loadFileURL(templateURL, allowingReadAccessTo: templateURL.deletingLastPathComponent())
    }
}
