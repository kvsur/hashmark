//
//  WebPreviewTemplate.swift
//  MarkdownApp
//
//  本地渲染模板（marked + css + highlight.js）的加载器。
//  静态预览（WebPreviewView）与 AI 流式预览（AIStreamingPreview）共用（DRY）。
//

import WebKit

enum WebPreviewTemplate {
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
