//
//  LanguagePreference.swift
//  MarkdownApp
//
//  界面语言偏好模型。持久化用 rawValue（存 UserDefaults），与 ThemePreference 同一形状。
//  rawValue 直接采用语言代码，这样偏好值即可用于解析 Locale，无需再维护一张映射表。
//  → 「偏好 → 实际生效的 Locale」的解析收敛在 LocalizationController（差异收敛封装层）。
//

import Foundation

/// 界面语言偏好。system 表示跟随系统。
enum LanguagePreference: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case german = "de"
    case russian = "ru"

    var id: String { rawValue }

    /// 显式选定的语言代码；system 为 nil（交由 LocalizationController 去匹配系统语言）。
    var languageCode: String? { self == .system ? nil : rawValue }

    /// App 支持的语言代码，按「兜底优先」排序——en 置首，
    /// 使 Bundle.preferredLocalizations 在系统语言全不匹配时天然落回英文（需求要求的兜底）。
    static let supportedCodes: [String] = allCases.compactMap(\.languageCode)

    /// 兜底语言：系统语言不在支持列表内时使用。
    static let fallbackCode = "en"

    /// 选择器显示用的「母语自称」（Deutsch / 日本語 / Русский…）；system 为 nil。
    ///
    /// 为什么用 verbatim 的 String 而非可本地化文案：用户正是在「看不懂当前界面语言」时才来切换语言，
    /// 若这些名字跟着当前 UI 语言变（界面是俄语时显示「Немецкий」），列表对他就毫无意义。
    /// 母语自称恒定不变，任何语言环境下都认得出自己的那一项。
    /// 同时也避免把 "Deutsch" 这类词当成 key 塞进 String Catalog、平白要求 7 份译文。
    var nativeName: String? {
        switch self {
        case .system: nil
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .german: "Deutsch"
        case .russian: "Русский"
        }
    }

    /// 语言的英文名，仅用于注入 AI prompt（见 AIPromptLocale）。
    /// prompt 骨架统一是英文，用英文语言名表达最稳，也避免模型误把语言名当正文语言的样例。
    /// 非界面文案，不进 String Catalog。
    var englishName: String? {
        switch self {
        case .system: nil
        case .english: "English"
        case .simplifiedChinese: "Simplified Chinese"
        case .traditionalChinese: "Traditional Chinese"
        case .japanese: "Japanese"
        case .korean: "Korean"
        case .german: "German"
        case .russian: "Russian"
        }
    }
}
