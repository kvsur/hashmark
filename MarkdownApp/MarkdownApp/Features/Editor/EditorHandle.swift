//
//  EditorHandle.swift
//  MarkdownApp
//
//  大纲/查找等上层 UI 向 UITextView 发导航命令的弱引用桥，避免把 UIKit 实例提升为页面状态。
//

import UIKit

final class EditorHandle {
    weak var textView: UITextView?
    var onScrollFraction: ((CGFloat) -> Void)?
    private var isApplyingSyncedScroll = false

    @MainActor
    func focus(range: NSRange) {
        guard let textView,
              range.location != NSNotFound,
              NSMaxRange(range) <= (textView.text as NSString).length else { return }
        textView.becomeFirstResponder()
        textView.selectedRange = range
        textView.scrollRangeToVisible(range)
    }

    @MainActor
    func reportScroll() {
        guard !isApplyingSyncedScroll, let scrollView = textView else { return }
        let travel = max(scrollView.contentSize.height - scrollView.bounds.height, 0)
        guard travel > 1 else { return }
        let fraction = min(max(scrollView.contentOffset.y / travel, 0), 1)
        onScrollFraction?(fraction)
    }

    @MainActor
    func scroll(toFraction fraction: CGFloat) {
        guard let scrollView = textView else { return }
        let travel = max(scrollView.contentSize.height - scrollView.bounds.height, 0)
        guard travel > 1 else { return }
        isApplyingSyncedScroll = true
        scrollView.setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: travel * min(max(fraction, 0), 1)),
            animated: false
        )
        DispatchQueue.main.async { [weak self] in self?.isApplyingSyncedScroll = false }
    }
}
