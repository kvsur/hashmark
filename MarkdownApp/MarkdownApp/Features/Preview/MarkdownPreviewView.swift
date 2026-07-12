//
//  MarkdownPreviewView.swift
//  MarkdownApp
//
//  Markdown 预览的 SwiftUI 封装：在底层 WebPreviewView 之上，统一处理
//  深浅色与「点外链弹 Safari 模态」。所有需要展示渲染结果的地方都用它，
//  避免每个调用方各写一遍外链处理（DRY）。
//

import SwiftUI

struct MarkdownPreviewView: View {
    let markdown: String
    /// 可选：上层传入以取底层 WebView（用于长截图等）。预览本身不需要它。
    var handle: PreviewHandle? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var externalLink: ExternalLink?

    var body: some View {
        WebPreviewView(
            markdown: markdown,
            colorScheme: colorScheme,
            onExternalLink: { url in externalLink = ExternalLink(url: url) },
            onWebViewReady: { webView in handle?.webView = webView }
        )
        .sheet(item: $externalLink) { link in
            SafariView(url: link.url)
                .ignoresSafeArea()
        }
    }
}

/// 包装外链 URL 以驱动 sheet(item:)。
private struct ExternalLink: Identifiable {
    let id = UUID()
    let url: URL
}
