//
//  AIPromptLocale.swift
//  MarkdownApp
//
//  注入 AI prompt 的「用户区域上下文」：界面语言 + 所在国家/地区 + 语言规则。
//
//  为什么 prompt 骨架统一用英文、语言差异只体现为这里注入的一小段：
//  模型对英文指令的遵循度最好、token 也更省；更重要的是只需维护一份 prompt——
//  改一条输出纪律不必同步改 7 份，加一种语言也是零成本。
//
//  语言规则是「双语义」的，这是本文件存在的核心原因：
//  - 生成的正文 = 内容 → 跟随文档/用户输入的语言（界面是德语但文档是中文时，续写仍出中文）
//  - 反问的问题 = 界面文本 → 跟随界面语言（说给用户听的话，他得看得懂）
//  两者语言可以不同，必须分开讲清楚，否则模型会把两者混为一谈。
//

import Foundation

enum AIPromptLocale {
    /// 界面语言的英文名，如 "German"。
    static var uiLanguageName: String {
        LocalizationController.resolved.englishName ?? "English"
    }

    /// 界面语言代码，如 "de"、"zh-Hans"。
    static var languageCode: String {
        LocalizationController.resolved.rawValue
    }

    /// 用户所在国家/地区代码，如 "DE"。
    ///
    /// 取自**设备区域**（Locale.current.region）而非语言偏好：用户完全可能「界面用英文但人在德国」，
    /// 从语言反推地区会推错（en → US？GB？）。取不到时为 nil，此时宁可不注入也不猜。
    static var regionCode: String? {
        Locale.current.region?.identifier
    }

    /// 注入 system prompt 的区域上下文与语言规则。
    static var contextBlock: String {
        var lines = [
            "User context: interface language = \(languageCode) (\(uiLanguageName)), "
                + "region = \(regionCode ?? "unknown").",
            "",
            "Language rules:",
            "- The document you write is content: keep it in the same language as the existing document"
                + " and the user's own input. Never switch it to the interface language.",
            "- Anything addressed to the user directly — clarifying questions and their option labels —"
                + " is interface text: write it in \(uiLanguageName), which is the language the user reads."
        ]
        // 地区未知时不编造：宁可少一条规则，也不让模型按错误的地区惯例排版日期/数字。
        if let regionCode {
            lines.append(
                "- Where dates, numbers, units, or currency appear, follow the conventions of \(regionCode)."
            )
        }
        return lines.joined(separator: "\n")
    }
}
