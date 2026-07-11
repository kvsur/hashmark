//
//  ContentView.swift
//  MarkdownApp
//
//  App 主壳：一个 NavigationStack，根为根目录的文件浏览器。
//  文件夹通过 navigationDestination 逐级下钻，支持无限级目录（S2）；
//  Markdown 文件下钻到文档屏（S3 预览 / S4 编辑，同屏切换）。
//

import SwiftUI

struct ContentView: View {
    private let store = FileStore()

    var body: some View {
        NavigationStack {
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
    }
}

#Preview {
    ContentView()
}
