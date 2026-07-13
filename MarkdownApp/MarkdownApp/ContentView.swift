//
//  ContentView.swift
//  MarkdownApp
//
//  App 主壳：一个 NavigationStack，根为根目录的文件浏览器。
//  文件夹通过 navigationDestination 逐级下钻，支持无限级目录（S2）；
//  Markdown 文件下钻到文档屏（S3 预览 / S4 编辑，同屏切换）。
//  外部分享/「打开方式」传入的文件经 onOpenURL → 选目录中间页 → 导入并跳到预览（S6）。
//

import SwiftUI

struct ContentView: View {
    @Environment(SettingsStore.self) private var settings
    private let store = FileStore()

    /// 显式导航路径，用于导入完成后以代码方式跳到新文件的预览。
    @State private var path: [DocumentNode] = []
    /// 待导入的外部文件（onOpenURL 传入），非 nil 时弹出选目录中间页。
    @State private var pendingImport: PendingImport?

    var body: some View {
        NavigationStack(path: $path) {
            FileBrowserView(store: store, directory: store.rootURL, isRoot: true)
                .navigationDestination(for: DocumentNode.self) { node in
                    // 同一目的地按类型分流：文件夹继续下钻，文档进入文档屏（预览/编辑）。
                    if node.isFolder {
                        FileBrowserView(store: store, directory: node.url)
                    } else {
                        DocumentView(store: store, node: node)
                    }
                }
        }
        // 其它 App 分享/打开传入文件时触发。
        .onOpenURL { url in
            pendingImport = PendingImport(url: url)
        }
        .sheet(item: $pendingImport) { item in
            ImportTargetPicker(store: store, sourceURL: item.url) { newURL in
                // 导入成功：直接把新文件推入栈，进入预览（S6.4）。
                path.append(DocumentNode(url: newURL, kind: .markdown, modifiedAt: .now))
            }
        }
        // 导入中间页关闭后（导入完成或取消）清理 Inbox 残留。
        .onChange(of: pendingImport?.id) { _, newID in
            if newID == nil { store.purgeInbox() }
        }
        // 主题：进入即应用当前偏好、之后随设置变化实时更新（窗口级，覆盖所有 sheet）。
        .onChange(of: settings.theme, initial: true) { _, newTheme in
            InterfaceStyleController.apply(newTheme)
        }
    }
}

#Preview {
    ContentView()
        .environment(SettingsStore())
}
