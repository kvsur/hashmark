//
//  InterfaceStyleController.swift
//  MarkdownApp
//
//  把主题偏好应用到「窗口级别」的界面风格。
//  为什么不用 SwiftUI 的 .preferredColorScheme：它不跨 sheet 呈现边界，会出现
//  「在设置页（sheet）里切主题、当前页不跟着变」。窗口级 overrideUserInterfaceStyle
//  对该窗口上的所有页面（含 sheet、alert）统一生效，是主题应用的单一收敛点。
//

import UIKit

enum InterfaceStyleController {
    /// 将主题偏好写入当前所有窗口。system → unspecified（交还系统跟随）。
    static func apply(_ theme: ThemePreference) {
        let style: UIUserInterfaceStyle
        switch theme {
        case .system: style = .unspecified
        case .light: style = .light
        case .dark: style = .dark
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}
