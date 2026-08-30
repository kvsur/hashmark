//
//  MarkdownAppApp.swift
//  MarkdownApp
//
//  Created by kvsur on 2026/7/12.
//

import SwiftUI

@main
struct MarkdownAppApp: App {
    // 全 App 共享的用户偏好；iOS 16 用 @StateObject 稳定持有，经 environmentObject 下发。
    @StateObject private var settings = SettingsStore()
    @StateObject private var documentLibrary = DocumentLibraryController()

    init() {
        // 取词拦截必须早于任何取词发生，故放在最前面；具体语言由 SettingsStore 初始化时应用。
        LocalizationController.bootstrap()
    }

    var body: some Scene {
        WindowGroup {
            // 主题应用在 ContentView 里以窗口级 overrideUserInterfaceStyle 生效
            // （覆盖所有 sheet/alert），见 InterfaceStyleController。
            ContentView()
                .environmentObject(settings)
                .environmentObject(documentLibrary)
                // 语言：取词本身由 LocalizationController 的取词拦截负责，这里注入 Locale 有两个作用——
                // 一是日期/数字格式化仍需正确的 Locale，二是它作为 SwiftUI 的重渲染信号：
                // 读了 \.locale 的视图会在语言变化时重算 body，从而重新取词。
                // 注入点必须在 App 根部：environment 只对作用域「内部」的视图生效，
                // 若在 ContentView 内部注入，挂在注入点之后的 sheet 会落在作用域外
                // （主题当年也栽在 sheet 边界上，见 InterfaceStyleController 的注释）。
                // 读 settings.language（而非 LocalizationController.current）是刻意的：
                // 前者是 @Published 属性，读它才会在语言变化时重算本 body、把新 Locale 推下去。
                .environment(\.locale, LocalizationController.resolve(settings.language))
        }
    }
}
