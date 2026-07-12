//
//  SafariView.swift
//  MarkdownApp
//
//  把 SFSafariViewController 包成 SwiftUI 可用的视图（App 内 Safari 模态）。
//  用于预览文档时点外链——在 App 内弹出原生 Safari，带地址栏/前进后退/完成，
//  不覆盖当前 Markdown 预览、也不离开 App。
//

import SwiftUI
import SafariServices

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
