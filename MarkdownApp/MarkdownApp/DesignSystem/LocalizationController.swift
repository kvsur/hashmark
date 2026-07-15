//
//  LocalizationController.swift
//  MarkdownApp
//
//  把语言偏好解析成「实际生效的语言」，是全 App 关于「现在该用哪种语言」的唯一答案来源。
//  与 InterfaceStyleController 并列：同为「用户偏好 → 全局生效」的封装层。
//
//  为什么不用 UserDefaults 的 AppleLanguages：那套要重启 App 才生效，
//  与「在设置页里切换、立刻看到」的产品预期相悖。
//
//  为什么不靠 .environment(\.locale) 取词（S1.2 实测结论）：
//  它只对 SwiftUI 的 Text/Section/Button 这类文本生效，
//  navigationTitle 走 UIKit 桥接、模型层走 Foundation，两者都只认进程级的 Locale.current，
//  换语言后会静默停留在旧语言。且 String(localized:locale:) 的 locale 参数只影响复数与数字格式，
//  并不选择语言包——显式传 locale 同样救不回来。
//
//  取词分两条路，各有各的入口，不能只用其中一条：
//  1) SwiftUI 的 Text("Key") / navigationTitle("Key") 等 LocalizedStringKey
//     → 由本文件替换 Bundle.main 主体类拦截，业务代码照常写、无需改动。
//  2) 需要拿到 String 的地方（模型层、与用户文件名共用同一参数的标题等）
//     → 必须走 LocalizationController.string(_:)。
//     Foundation 的 String(localized:) **不经过** Bundle.localizedString(forKey:value:table:)，
//     因此拦截不到它：直接用 String(localized:) 会静默按系统语言取词，
//     在「App 内切了语言、但系统语言是另一种」时就会露馅（首页标题曾因此固定显示中文）。
//

import Foundation

enum LocalizationController {
    /// 当前生效的 Locale。供日期/数字/字节等格式化使用。
    private(set) static var current: Locale = .current

    /// 当前生效的**具体**语言（已解析，绝不会是 .system）。
    /// 与 current 的区别：这里要的是「哪一种语言」本身，供 AI prompt 注入语言名/语言码。
    private(set) static var resolved: LanguagePreference = .english

    /// 当前语言对应的 .lproj bundle；nil 表示回退到 Bundle.main 自身（即源语言 en）。
    fileprivate static var languageBundle: Bundle?

    /// 安装取词拦截。必须在任何取词发生前调用一次（App init）。
    static func bootstrap() {
        _ = installOnce
    }

    private static let installOnce: Void = {
        object_setClass(Bundle.main, LocalizedBundle.self)
    }()

    /// 应用语言偏好：解析出语言代码，并把取词导向该语言的 .lproj。
    ///
    /// 由 SettingsStore 在偏好写入时同步调用（而非在视图的 onChange 里）——必须赶在 SwiftUI 重渲染之前完成，
    /// 否则这一帧会用旧语言包取词、界面停留在上一种语言。
    static func apply(_ preference: LanguagePreference) {
        let code = resolveCode(preference)
        current = Locale(identifier: code)
        resolved = LanguagePreference(rawValue: code) ?? .english
        // en 是源语言，构建产物里没有 en.lproj（key 本身即英文），此时置 nil 回退到 main bundle。
        languageBundle = Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:))
    }

    /// 偏好 → Locale。供视图层注入 environment 用。
    static func resolve(_ preference: LanguagePreference) -> Locale {
        Locale(identifier: resolveCode(preference))
    }

    /// 取词并拿到 String。**凡是需要 String（而非 Text/LocalizedStringKey）的地方一律走这里。**
    ///
    /// 不要直接用 Foundation 的 String(localized:)：它不经过 Bundle.localizedString(forKey:value:table:)，
    /// 因而躲开了本文件的取词拦截，会按系统语言取词——「App 内切德语但系统是中文」时静默出错。
    /// 这里显式把语言包交给 bundle 参数，是唯一可靠的做法。
    ///
    /// 支持插值与复数，用法与 String(localized:) 一致：
    ///   LocalizationController.string("Documents")
    ///   LocalizationController.string("\(count) items")
    static func string(_ value: String.LocalizationValue) -> String {
        String(localized: value, bundle: languageBundle ?? .main)
    }

    /// 偏好 → 语言代码。优先级：用户存储偏好 → 系统语言 → 英文兜底。
    /// 返回「代码」而非 Locale，是因为注入 AI system prompt 时要的正是语言码。
    static func resolveCode(_ preference: LanguagePreference) -> String {
        // 第一优先级：用户在设置里显式选定的语言。
        if let code = preference.languageCode { return code }

        // 第二优先级：跟随系统。系统的偏好语言常带地区/脚本后缀（zh-Hans-CN、de-DE、en-GB），
        // 不能直接字符串比对；交给 Foundation 的规范匹配器按 BCP-47 规则匹配到我们支持的语言。
        let matched = Bundle.preferredLocalizations(from: LanguagePreference.supportedCodes).first

        // 第三优先级：兜底英文。系统语言不在支持列表内（如法语）时走到这里。
        // supportedCodes 已把 en 排在首位，匹配器无命中时本就会返回它；此处再显式收口一次，
        // 不把兜底行为寄托在第三方 API 的默认值上。
        guard let matched, LanguagePreference.supportedCodes.contains(matched) else {
            return LanguagePreference.fallbackCode
        }
        return matched
    }
}

/// Bundle.main 被替换成的主体类：把取词转发给当前语言的 .lproj。
/// 未选定语言包时原样走父类实现（即源语言英文）。
private final class LocalizedBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        guard let bundle = LocalizationController.languageBundle else {
            return super.localizedString(forKey: key, value: value, table: tableName)
        }
        return bundle.localizedString(forKey: key, value: value, table: tableName)
    }
}
