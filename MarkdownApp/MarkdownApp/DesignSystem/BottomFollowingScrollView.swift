//
//  BottomFollowingScrollView.swift
//  MarkdownApp
//
//  iOS 16+ 的流式内容底部跟随容器。更新令牌变化后等待本轮布局完成，再滚到末端锚点。
//

import SwiftUI

struct BottomFollowingScrollView<UpdateToken: Equatable, Content: View>: View {
    let updateToken: UpdateToken
    private let content: Content
    private let bottomID = "bottom-following-scroll-anchor"

    init(
        updateToken: UpdateToken,
        @ViewBuilder content: () -> Content
    ) {
        self.updateToken = updateToken
        self.content = content()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
                Color.clear
                    .frame(height: 1)
                    .id(bottomID)
            }
            .onAppear { scrollToBottom(using: proxy) }
            .onChange(of: updateToken) { _ in scrollToBottom(using: proxy) }
        }
    }

    private func scrollToBottom(using proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            proxy.scrollTo(bottomID, anchor: .bottom)
        }
    }
}
