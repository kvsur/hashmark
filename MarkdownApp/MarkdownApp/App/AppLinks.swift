//
//  AppLinks.swift
//  MarkdownApp
//
//  用户可见的官方外链集中在这里，避免商店元数据与 App 内入口漂移。
//

import Foundation

nonisolated enum AppLinks {
    private static let privacyPolicyBase = URL(string: "https://kvsur.github.io/hashmark/privacy/")!

    /// 隐私页优先使用 URL 中的语言，避免 App 内已切换语言时被 Safari 的系统语言覆盖。
    static var privacyPolicy: URL {
        var components = URLComponents(url: privacyPolicyBase, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "lang", value: LocalizationController.resolved.rawValue)
        ]
        return components.url ?? privacyPolicyBase
    }
}
