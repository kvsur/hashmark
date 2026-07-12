//
//  ShareSheet.swift
//  MarkdownApp
//
//  UIActivityViewController 的 SwiftUI 包装：把任意可分享项（图片/文件 URL/文本）
//  交给系统分享面板。抽成通用件，供预览分享等场景复用（DRY）。
//

import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// 包装待分享项以驱动 sheet(item:)。
struct ShareItems: Identifiable {
    let id = UUID()
    let items: [Any]
}
