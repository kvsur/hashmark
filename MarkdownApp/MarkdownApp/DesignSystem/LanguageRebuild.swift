//
//  LanguageRebuild.swift
//  MarkdownApp
//
//  让一棵视图子树在界面语言变化时整体重建。
//
//  为什么需要它（S1.2 实测结论）：切换语言后，SwiftUI 的 Text/Section/Button 会随 \.locale 自动重新取词，
//  但 navigationTitle 走 UIKit 桥接，只在 body 重算的那一刻取一次词——语言变了它不会自己更新，
//  会静默停留在上一种语言。换一个随语言变化的身份，强制 SwiftUI 重建子树、让标题重新取词。
//
//  为什么加在 NavigationStack 而不是 App 根部：根部重建会把已弹出的 sheet 一并掀掉
//  （用户正是在设置页的 sheet 里切语言的，那样会被弹回首页）。加在每个 NavigationStack 上，
//  sheet 能原地换语言、留在原处。
//

import SwiftUI

private struct LanguageRebuildModifier: ViewModifier {
    @Environment(SettingsStore.self) private var settings

    func body(content: Content) -> some View {
        content.id(settings.language)
    }
}

extension View {
    /// 界面语言变化时重建本视图。**每个 NavigationStack 都要加**，否则其 navigationTitle 换语言后不更新。
    func rebuildsOnLanguageChange() -> some View {
        modifier(LanguageRebuildModifier())
    }
}
