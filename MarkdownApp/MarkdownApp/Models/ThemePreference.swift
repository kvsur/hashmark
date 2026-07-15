//
//  ThemePreference.swift
//  MarkdownApp
//
//  外观主题偏好模型。持久化用 rawValue（存 UserDefaults）。
//  → UIKit 界面风格的映射收敛在 InterfaceStyleController（差异收敛封装层）。
//

import SwiftUI

/// 外观主题偏好。system 表示跟随系统。
enum ThemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    /// 设置页 Picker 显示用标签。取 LocalizedStringKey 而非 String——
    /// String 会被 Text 当作字面量原样显示、绕过本地化。
    var label: LocalizedStringKey {
        switch self {
        case .system: "Follow System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}
