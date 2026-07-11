//
//  ContentView.swift
//  MarkdownApp
//
//  App 主壳：一个 NavigationStack，根为根目录的文件浏览器。
//  文件夹通过 navigationDestination 逐级下钻，支持无限级目录（S2）。
//  文档的预览/编辑（S3/S4）后续接入。
//

import SwiftUI

struct ContentView: View {
    private let store = FileStore()

    var body: some View {
        NavigationStack {
            FileBrowserView(store: store, directory: store.rootURL, isRoot: true)
                .navigationDestination(for: DocumentNode.self) { node in
                    // 目前只有文件夹会被下钻；文档预览留待 S3。
                    FileBrowserView(store: store, directory: node.url)
                }
        }
    }
}

#Preview {
    ContentView()
}
