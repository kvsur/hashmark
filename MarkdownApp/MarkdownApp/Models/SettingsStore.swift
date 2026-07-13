//
//  SettingsStore.swift
//  MarkdownApp
//
//  用户偏好存储服务：以 UserDefaults 持久化外观主题（不进 Documents）。
//  @Observable 供根视图响应式应用主题；写入即落盘。
//  语言切换本期仅为 UI 占位（见 SettingsView），暂无需持久化，待真正做多语言时在此扩展。
//

import Foundation

@Observable
final class SettingsStore {
    /// 外观主题。写入即持久化；缺省 .system（跟随系统）。
    /// 主题的实际应用（窗口级）在 ContentView 监听变化后交给 InterfaceStyleController。
    var theme: ThemePreference {
        didSet { defaults.set(theme.rawValue, forKey: Keys.theme) }
    }

    private let defaults: UserDefaults
    private enum Keys { static let theme = "settings.theme" }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 有本地存储则优先用存储值，否则默认跟随系统。
        let stored = defaults.string(forKey: Keys.theme).flatMap(ThemePreference.init(rawValue:))
        self.theme = stored ?? .system
    }
}
