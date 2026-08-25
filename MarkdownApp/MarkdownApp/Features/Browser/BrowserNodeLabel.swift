//
//  BrowserNodeLabel.swift
//  MarkdownApp
//
//  文件浏览器行的纯展示内容，不持有导航或磁盘操作。
//

import SwiftUI

struct BrowserNodeLabel: View {
    let node: DocumentNode

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: node.systemImage)
                .font(.title3)
                .foregroundStyle(node.isFolder ? Color.accentColor : .secondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(node.displayName)
                    .font(Theme.mono())
                Text(node.metadataText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
