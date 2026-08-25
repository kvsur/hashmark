//
//  EditorLineActionButton.swift
//  MarkdownApp
//
//  编辑模式里「跟随光标」的小 AI 按钮：放在光标上方（避免被点击的手指遮挡；贴近顶部时动态翻到光标下方），
//  点它选中当前块/段落并直接进 AI 润色。取代早期的左侧 gutter 竖条——左缘竖条太窄难点；改成一个
//  小小的、不喧宾夺主的圆钮跟着光标走，一点即用。仅在编辑（获得焦点）且光标行可见时出现，其余时候隐藏。
//

import UIKit

/// 承载「UITextView + 行内小按钮」的容器。仅多做一件事：尺寸变化时回调 onLayout，
/// 让上层在旋转/分栏/首帧布局后重新摆放按钮（位置依赖布局与 caretRect）。
final class EditorContainerView: UIView {
    var onLayout: (() -> Void)?
    private var lastSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastSize else { return }
        lastSize = bounds.size
        onLayout?()
    }
}

/// 跟随光标行的小圆钮：半透明底 + sparkles 图标，刻意小而低调（用户所谓「小小的憋憋的按钮」）。
final class EditorLineActionButton: UIButton {
    static let size: CGFloat = 30

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: Self.size, height: Self.size))
        backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.92)
        tintColor = .systemIndigo   // AI 语义的低饱和着色，不用品牌大渐变以保持克制
        let symbol = UIImage(systemName: "sparkles",
                             withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        setImage(symbol, for: .normal)
        // 细描边 + 轻阴影，让它从正文里微微浮起但不刺眼。
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.separator.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1)
        accessibilityLabel = String(localized: "AI")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}
