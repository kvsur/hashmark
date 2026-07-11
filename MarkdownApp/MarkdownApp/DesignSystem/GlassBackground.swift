//
//  GlassBackground.swift
//  MarkdownApp
//
//  液态玻璃背景的统一封装（关键抽象层）。
//  - iOS 26+：使用系统原生 Liquid Glass（.glassEffect）。
//  - iOS 18–25：优雅降级为材质模糊（.ultraThinMaterial）。
//
//  全 App 通过 `.glassBackground()` 调用，把「可用性判断」收敛到这一个地方，
//  避免在业务代码里到处写 if #available。
//
//  注：iOS 26 的导航栏 / 工具栏会「自动」套上 Liquid Glass，无需这里处理；
//  本封装用于我们自己的卡片、浮层等自定义表面。
//

import SwiftUI

struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat = Theme.cornerRadius

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // iOS 26+ 原生液态玻璃
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            // iOS 18–25 材质降级
            content.background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius)
            )
        }
    }
}

extension View {
    /// 给当前视图套一层「液态玻璃 / 材质」背景。
    func glassBackground(cornerRadius: CGFloat = Theme.cornerRadius) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius))
    }
}
