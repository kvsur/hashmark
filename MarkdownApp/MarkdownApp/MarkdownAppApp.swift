//
//  MarkdownAppApp.swift
//  MarkdownApp
//
//  Created by kvsur on 2026/7/12.
//

import SwiftUI

@main
struct MarkdownAppApp: App {
    // 全 App 共享的用户偏好；@State 持有以配合 @Observable，经 environment 下发。
    @State private var settings = SettingsStore()

    var body: some Scene {
        WindowGroup {
            // 主题应用在 ContentView 里以窗口级 overrideUserInterfaceStyle 生效
            // （覆盖所有 sheet/alert），见 InterfaceStyleController。
            ContentView()
                .environment(settings)
        }
    }
}
