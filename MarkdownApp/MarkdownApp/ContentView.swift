//
//  ContentView.swift
//  MarkdownApp
//
//  App 主壳（S1）：导航结构 + 占位文件列表 + 右上角「预览/编辑」模式切换器。
//  这一版只搭骨架；真实的文件系统目录（S2）、预览（S3）、编辑（S4）后续接入。
//

import SwiftUI

/// App 的显示模式：预览 / 编辑。由右上角切换器驱动。
/// 类比前端：这就是一个受控的 state 枚举。
enum AppMode: String, CaseIterable, Identifiable {
    case preview = "预览"
    case edit = "编辑"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .preview: "eye"
        case .edit: "square.and.pencil"
        }
    }
}

struct ContentView: View {
    // @State ≈ 组件内部状态；变化会自动触发界面刷新。
    @State private var mode: AppMode = .preview

    // S1 占位数据：S2 会替换成真实的文件系统目录树。
    private let placeholderItems = [
        "📁 我的笔记",
        "📁 项目文档",
        "📄 README.md",
        "📄 待办清单.md"
    ]

    var body: some View {
        NavigationStack {
            List(placeholderItems, id: \.self) { item in
                Text(item)
                    .font(Theme.mono())
            }
            .navigationTitle("文档")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // 右上角 预览/编辑 切换（S1 占位，S4 接真实逻辑）
                    Picker("模式", selection: $mode) {
                        ForEach(AppMode.allCases) { m in
                            Label(m.rawValue, systemImage: m.systemImage).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
