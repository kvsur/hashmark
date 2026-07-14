//
//  HorizontalSwitchGesture.swift
//  MarkdownApp
//
//  可复用的「水平滑动切换」手势封装：向左 / 向右滑动分别触发回调。
//  用途是给「预览 ↔ 编辑」这类左右分页式切换加手势，逻辑收敛在一处，
//  业务视图只声明「左滑做什么、右滑做什么」，不必各自重写方向判定与冲突处理。
//
//  两个关键取舍：
//  1) 用 simultaneousGesture 而非 gesture——底层是 WebView（垂直滚动）或
//     TextEditor（选择/滚动），独占手势会抢掉它们；同时识别、仅在「水平位移
//     明显压过垂直且超过阈值」时才动作，滚动与选择都不受影响。
//  2) 右滑保留最左侧边缘给系统返回手势：只有起点离左边缘足够远的右滑才触发切换，
//     贴边右滑仍是「返回上一页」，两者不打架。
//

import SwiftUI

struct HorizontalSwitchModifier: ViewModifier {
    var onSwipeLeft: () -> Void
    var onSwipeRight: () -> Void

    /// 触发所需的最小水平位移（pt）。太小会误触，太大会显得迟钝。
    private let distanceThreshold: CGFloat = 60
    /// 水平位移需至少为垂直位移的这个倍数，才认定为「横滑」而非斜滑/竖滑。
    private let horizontalDominance: CGFloat = 1.5
    /// 右滑时，起点需离左边缘至少这么远，才视为切换；更靠边则让给系统返回手势。
    private let edgeGuard: CGFloat = 40

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > abs(dy) * horizontalDominance,
                          abs(dx) > distanceThreshold else { return }
                    if dx < 0 {
                        onSwipeLeft()
                    } else if value.startLocation.x > edgeGuard {
                        onSwipeRight()
                    }
                }
        )
    }
}

extension View {
    /// 给视图加「水平滑动切换」：左滑触发 `onSwipeLeft`，右滑（非贴左边缘）触发 `onSwipeRight`。
    func horizontalSwitch(
        onSwipeLeft: @escaping () -> Void,
        onSwipeRight: @escaping () -> Void
    ) -> some View {
        modifier(HorizontalSwitchModifier(onSwipeLeft: onSwipeLeft, onSwipeRight: onSwipeRight))
    }
}
