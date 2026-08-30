//
//  CompatiblePresentation.swift
//  MarkdownApp
//
//  收敛 iOS 16.4 新增的 presentation 行为；iOS 16.0–16.3 保留系统默认呈现。
//

import SwiftUI

private struct ScrollablePresentationContentModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.presentationContentInteraction(.scrolls)
        } else {
            content
        }
    }
}

private struct CompactPopoverPresentationModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.presentationCompactAdaptation(.popover)
        } else {
            content
        }
    }
}

extension View {
    /// iOS 16.4+ 让 sheet 内容滚动优先；16.0–16.3 使用系统默认交互。
    func compatibleScrollablePresentationContent() -> some View {
        modifier(ScrollablePresentationContentModifier())
    }

    /// iOS 16.4+ 在 compact 环境保持 popover；16.0–16.3 使用系统默认适配。
    func compatibleCompactPopover() -> some View {
        modifier(CompactPopoverPresentationModifier())
    }
}
