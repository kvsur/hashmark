//
//  AppEmptyStateView.swift
//  MarkdownApp
//
//  统一空状态：iOS 17+ 使用系统 ContentUnavailableView，iOS 16 保持同等信息层级与无障碍语义。
//

import SwiftUI

struct AppEmptyStateView<Description: View, Actions: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    private let description: Description
    private let actions: Actions

    init(
        _ title: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder description: () -> Description,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.systemImage = systemImage
        self.description = description()
        self.actions = actions()
    }

    var body: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                description
            } actions: {
                actions
            }
        } else {
            VStack(spacing: 16) {
                VStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.system(size: 44, weight: .regular))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.title3.weight(.semibold))
                    description
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)

                actions
            }
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

extension AppEmptyStateView where Actions == EmptyView {
    init(
        _ title: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder description: () -> Description
    ) {
        self.init(
            title,
            systemImage: systemImage,
            description: description,
            actions: EmptyView.init
        )
    }
}

extension AppEmptyStateView where Description == EmptyView, Actions == EmptyView {
    init(_ title: LocalizedStringKey, systemImage: String) {
        self.init(
            title,
            systemImage: systemImage,
            description: EmptyView.init,
            actions: EmptyView.init
        )
    }
}
