//
//  AISupportedProvidersSection.swift
//  MarkdownApp
//
//  常驻展示五家正式支持范围。品牌名保持官方拼写，不显示兼容协议分组。
//

import SwiftUI

struct AISupportedProvidersSection: View {
    var body: some View {
        Section("Supported Providers") {
            Label {
                Text(verbatim: AIProvider.officiallySupported.map(\.displayName).joined(separator: ", "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "network")
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
