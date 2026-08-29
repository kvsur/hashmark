//
//  SettingsStore.swift
//  MarkdownApp
//
//  用户偏好存储服务：以 UserDefaults 持久化外观主题与界面语言（不进 Documents）。
//  ObservableObject 供 iOS 16+ 根视图响应式应用主题/语言；写入即落盘。
//

import Combine
import Foundation

final class SettingsStore: ObservableObject {
    /// 外观主题。写入即持久化；缺省 .system（跟随系统）。
    /// 主题的实际应用（窗口级）在 ContentView 监听变化后交给 InterfaceStyleController。
    @Published var theme: ThemePreference {
        didSet { defaults.set(theme.rawValue, forKey: Keys.theme) }
    }

    /// 界面语言。写入即持久化；缺省 .system（跟随系统语言，解析规则见 LocalizationController）。
    ///
    /// 为什么在 didSet 里就把语言应用下去（主题却是在 ContentView 的 onChange 里应用）：
    /// 取词发生在 SwiftUI 重渲染的过程中，而 onChange 在重渲染之后才执行——
    /// 那样这一帧会用旧语言包取词，界面会慢一拍。didSet 与赋值同步，能确保重渲染时语言包已就位。
    @Published var language: LanguagePreference {
        didSet {
            defaults.set(language.rawValue, forKey: Keys.language)
            LocalizationController.apply(language)
        }
    }

    private let defaults: UserDefaults
    private enum Keys {
        static let theme = "settings.theme"
        static let language = "settings.language"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 有本地存储则优先用存储值，否则默认跟随系统。
        let stored = defaults.string(forKey: Keys.theme).flatMap(ThemePreference.init(rawValue:))
        self.theme = stored ?? .system
        // 语言同理：存储值优先于系统语言，这是需求要求的第一优先级。
        let storedLanguage = defaults.string(forKey: Keys.language).flatMap(LanguagePreference.init(rawValue:))
        self.language = storedLanguage ?? .system
        // didSet 不会因 init 内的赋值触发，故首帧的语言包在此显式就位。
        LocalizationController.apply(self.language)
    }
}
