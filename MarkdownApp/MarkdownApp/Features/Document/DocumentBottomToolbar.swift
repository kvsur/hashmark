//
//  DocumentBottomToolbar.swift
//  MarkdownApp
//
//  文档底栏的版本差异封装：iOS 26 使用 ToolbarSpacer，iOS 16–25 用普通 Spacer 保持分组。
//

import SwiftUI

struct DocumentBottomToolbar<NavigationControls: View, PrimaryAction: View>: ToolbarContent {
    private let navigationControls: NavigationControls
    private let primaryAction: PrimaryAction

    init(
        @ViewBuilder navigationControls: () -> NavigationControls,
        @ViewBuilder primaryAction: () -> PrimaryAction
    ) {
        self.navigationControls = navigationControls()
        self.primaryAction = primaryAction()
    }

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItemGroup(placement: .bottomBar) {
                navigationControls
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                primaryAction
            }
        } else {
            ToolbarItemGroup(placement: .bottomBar) {
                navigationControls
                Spacer()
                primaryAction
            }
        }
    }
}
