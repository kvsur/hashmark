//
//  MarkdownTextView.swift
//  MarkdownApp
//
//  编辑器底座：UIViewRepresentable 包 UITextView，替代裸 SwiftUI TextEditor。
//  为什么要它：SwiftUI TextEditor 拿不到「选区气泡菜单」的自定义入口，也拿不到文本布局 rect——
//  这两点分别是「选中文字 → AI 润色」与「跟随光标行的块操作按钮」的前提。EditorView 的注释早已预留
//  「将来替换为 UIViewRepresentable 包 UITextView，对外接口不变」这条路，此文件即其落地。
//
//  对外仍是受控组件：只接一个 @Binding text；从哪加载、何时保存仍是 DocumentView 的事。
//  行为对齐原 TextEditor：等宽字体、无自动更正/大写、无智能标点（Markdown 源码）、透明背景、左右内边距。
//
//  返回的是一个容器：UITextView 打底 +「跟随光标」的小 AI 按钮（放光标上方，避免被手指遮挡，贴顶时翻下方）。
//  按钮只在编辑且光标行可见时出现，点它选中当前块/段落并直接发起润色；平时几乎无存在感，不影响查看与编辑。
//
//  类比前端：相当于把一个「非受控的原生 textarea」包成受控组件——value 由外部 state 驱动，
//  oninput 回写 state；内部只负责渲染、光标与那枚行内小按钮，不持有业务逻辑。
//

import SwiftUI
import UIKit

struct MarkdownTextView: UIViewRepresentable {
    @Binding var text: String
    var handle: EditorHandle? = nil
    var autofocus = false
    var onAutofocusConsumed: () -> Void = {}

    /// 请求对某段文本做 AI 润色：来自「选区气泡菜单点 AI」或「行内小按钮」，交出选中文本与其 NSRange。
    /// 上层（DocumentView）据此发起润色会话，并在接受后按 range 回填。默认空实现，便于未接线时使用。
    var onRequestAIRefine: (_ selectedText: String, _ range: NSRange) -> Void = { _, _ in }

    /// 左右内边距（pt）：对齐原 EditorView 的 .padding(.horizontal, 12) 观感。
    /// 只给左右、不给上下——底部要让内容能滚到浮动工具栏下方（与原实现同一取舍）。
    private let horizontalInset: CGFloat = 12

    func makeUIView(context: Context) -> UIView {
        let container = EditorContainerView()
        // 尺寸变化（首帧/旋转/分栏）后重摆按钮，保证跟随对齐。
        container.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.repositionLineButton()
        }

        let tv = MarkdownEditorTextView()
        tv.delegate = context.coordinator
        tv.onEditorCommand = { [weak coordinator = context.coordinator] command in
            coordinator?.perform(command)
        }

        // 等宽字体：对应 Theme.mono(16)。SwiftUI 的 Font 无法直接喂给 UITextView，这里用等价的 UIFont。
        tv.font = UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
        tv.textColor = .label                      // 随深浅色自动切换
        tv.backgroundColor = .clear                // 等价原 .scrollContentBackground(.hidden)：露出系统底色

        // Markdown 源码：一律关掉更正/大写/智能标点，避免把 `"`、`--`、`...` 悄悄改成排版字符。
        tv.autocorrectionType = .no
        tv.autocapitalizationType = .none
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        tv.smartInsertDeleteType = .no
        tv.spellCheckingType = .no

        // 内边距：lineFragmentPadding 归零后，用 textContainerInset 精确控制左右 12pt。
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainerInset = UIEdgeInsets(top: 8, left: horizontalInset, bottom: 8, right: horizontalInset)

        tv.alwaysBounceVertical = true
        tv.keyboardDismissMode = .interactive
        tv.isFindInteractionEnabled = true
        let keyboardBar = EditorKeyboardBar()
        keyboardBar.onCommand = { [weak coordinator = context.coordinator] command in
            coordinator?.perform(command)
        }
        keyboardBar.onUndo = { [weak coordinator = context.coordinator] in
            coordinator?.undo()
        }
        keyboardBar.onRedo = { [weak coordinator = context.coordinator] in
            coordinator?.redo()
        }
        keyboardBar.onDismissKeyboard = { [weak tv] in tv?.resignFirstResponder() }
        tv.inputAccessoryView = keyboardBar
        tv.text = text
        tv.frame = container.bounds
        tv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(tv)

        let button = EditorLineActionButton()
        button.isHidden = true
        button.addTarget(context.coordinator, action: #selector(Coordinator.lineButtonTapped), for: .touchUpInside)
        container.addSubview(button)

        context.coordinator.textView = tv
        context.coordinator.lineButton = button
        handle?.textView = tv
        context.coordinator.scheduleHighlight()
        DispatchQueue.main.async { [weak coordinator = context.coordinator] in
            coordinator?.performInitialFocusIfNeeded()
        }
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // 让 Coordinator 始终指向最新的 self，保证回写与回调走到当前这份 @Binding / 闭包。
        context.coordinator.parent = self
        guard let tv = context.coordinator.textView else { return }
        handle?.textView = tv
        context.coordinator.performInitialFocusIfNeeded()

        // 只在外部 text 与内部不一致时才赋值：用户键入时二者已相等（textViewDidChange 刚回写过），
        // 直接 return 避免重设 text 导致光标跳动/丢失；仅当外部驱动改动（AI 回填、切换文档）才同步。
        guard tv.text != text else { return }
        let selected = tv.selectedRange
        tv.text = text
        let maxLocation = (text as NSString).length
        tv.selectedRange = NSRange(location: min(selected.location, maxLocation), length: 0)
        context.coordinator.scheduleHighlight()
        context.coordinator.repositionLineButton()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// UITextViewDelegate 桥：文本回写 + 选区气泡菜单加「AI」+ 驱动行内小按钮跟随。
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MarkdownTextView
        weak var textView: UITextView?
        weak var lineButton: EditorLineActionButton?
        private var isApplyingMutation = false
        private var didPerformInitialFocus = false
        private var highlightWorkItem: DispatchWorkItem?

        init(_ parent: MarkdownTextView) { self.parent = parent }

        func performInitialFocusIfNeeded() {
            guard parent.autofocus, !didPerformInitialFocus, let textView else { return }
            didPerformInitialFocus = true
            textView.selectedRange = NSRange(location: 0, length: 0)
            textView.becomeFirstResponder()
            parent.onAutofocusConsumed()
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            if !isApplyingMutation { scheduleHighlight() }
            repositionLineButton()
        }

        /// 智能输入的唯一接入点。规则不确定或 IME 正在组合时返回 true，完全交还 UIKit。
        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            guard !isApplyingMutation else { return true }
            let context = editingContext(for: textView)
            let edit = MarkdownProposedEdit(range: range, replacementText: text)
            guard let mutation = MarkdownEditingEngine.mutation(for: edit, in: context) else {
                return true
            }
            apply(mutation, to: textView)
            return false
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            repositionLineButton()
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            repositionLineButton()
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            lineButton?.isHidden = true
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            parent.handle?.reportScroll()
            repositionLineButton()
        }

        // MARK: - 选区气泡菜单

        /// 定制选区气泡菜单（复制/剪切… 那一排）：仅在有非空选区时，把「AI」放到系统建议项的**最前**，
        /// 确保它出现在菜单第一层而非溢出到第二页。点它把「选中文本 + range」抛给上层走润色链路。
        func textView(_ textView: UITextView,
                      editMenuForTextIn range: NSRange,
                      suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard range.length > 0 else { return nil }
            let selected = (textView.text as NSString).substring(with: range)
            let aiAction = UIAction(
                title: String(localized: "AI"),
                image: UIImage(systemName: "wand.and.stars")   // 与现有润色动作同一 SF Symbol，无 emoji
            ) { [weak textView] _ in
                // 用触发瞬间的实时选区，避免菜单展示期间选区变动导致 range 过期；异常时回退到构建时的 range。
                let live = textView?.selectedRange ?? range
                let effectiveRange = live.length > 0 ? live : range
                let effectiveText = (textView?.text as NSString?)?.substring(with: effectiveRange) ?? selected
                self.parent.onRequestAIRefine(effectiveText, effectiveRange)
            }
            return UIMenu(children: [aiAction] + suggestedActions)
        }

        // MARK: - 行内小按钮

        @objc func dismissKeyboard() {
            textView?.resignFirstResponder()
        }

        func perform(_ command: MarkdownEditorCommand) {
            guard let textView else { return }
            let context = editingContext(for: textView)
            guard let mutation = MarkdownEditingEngine.mutation(for: command, in: context) else { return }
            apply(mutation, to: textView)
            Haptics.soft()
        }

        /// 软件键盘栏与系统 Command-Z 共用 UITextView 的撤销栈；连续点击可逐步回退
        /// 普通输入和 Markdown 命令。没有可撤销内容时保持安静，不制造无意义反馈。
        func undo() {
            guard let undoManager = textView?.undoManager, undoManager.canUndo else { return }
            undoManager.undo()
            Haptics.soft()
        }

        /// 与 Undo 成对使用；执行新编辑后 UndoManager 会按系统规则清空已失效的 redo 分支。
        func redo() {
            guard let undoManager = textView?.undoManager, undoManager.canRedo else { return }
            undoManager.redo()
            Haptics.soft()
        }

        private func editingContext(for textView: UITextView) -> MarkdownEditingContext {
            let markedRange: NSRange?
            if let marked = textView.markedTextRange {
                let location = textView.offset(from: textView.beginningOfDocument, to: marked.start)
                let length = textView.offset(from: marked.start, to: marked.end)
                markedRange = NSRange(location: location, length: length)
            } else {
                markedRange = nil
            }
            return MarkdownEditingContext(
                text: textView.text,
                selectedRange: textView.selectedRange,
                markedTextRange: markedRange
            )
        }

        /// 原子应用一条 mutation，并手动注册逆 mutation；逆操作执行时会自然注册 redo。
        private func apply(_ mutation: MarkdownTextMutation, to textView: UITextView) {
            let context = editingContext(for: textView)
            guard mutation.isValid(in: context) else { return }
            let oldText = (textView.text as NSString).substring(with: mutation.range)
            let oldSelection = textView.selectedRange
            let reverse = MarkdownTextMutation(
                range: NSRange(location: mutation.range.location, length: mutation.replacementText.utf16.count),
                replacementText: oldText,
                selectedRangeAfter: oldSelection,
                kind: mutation.kind
            )
            textView.undoManager?.registerUndo(withTarget: self) { [weak textView] target in
                guard let textView else { return }
                target.apply(reverse, to: textView)
            }

            let offset = textView.contentOffset
            isApplyingMutation = true
            textView.textStorage.replaceCharacters(in: mutation.range, with: mutation.replacementText)
            textView.selectedRange = mutation.selectedRangeAfter
            parent.text = textView.text
            isApplyingMutation = false
            textView.setContentOffset(offset, animated: false)
            scheduleHighlight()
            repositionLineButton()
        }

        func scheduleHighlight() {
            highlightWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, let textView = self.textView else { return }
                self.isApplyingMutation = true
                MarkdownSyntaxHighlighter.apply(to: textView)
                self.isApplyingMutation = false
            }
            highlightWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
        }

        @objc func lineButtonTapped() {
            guard let tv = textView else { return }
            let ns = tv.text as NSString
            let range = EditorBlockScanner.enclosingSelection(at: tv.selectedRange.location, in: tv.text)
            guard range.length > 0,
                  range.location >= 0,
                  range.location + range.length <= ns.length else { return }
            let selectedText = ns.substring(with: range)
            Haptics.light()
            tv.selectedRange = range          // 视觉上先选中当前块/段落，返回编辑器时保持高亮
            parent.onRequestAIRefine(selectedText, range)
        }

        /// 把小按钮摆到光标**上方**、横向对齐光标：放上方是为了不被点击的手指遮挡（手指在光标处）。
        /// 动态避让：贴近可视顶部（第一行 / 灵动岛区域）放不下时翻到光标**下方**；横向夹在左右缘内。
        /// 只有当光标行真正滚出可视区时才隐藏——避免第一行被误判越界而「出不来」。
        func repositionLineButton() {
            guard let tv = textView, let button = lineButton else { return }
            guard tv.isFirstResponder, let caretPosition = tv.selectedTextRange?.end else {
                button.isHidden = true
                return
            }
            let caret = tv.caretRect(for: caretPosition)
            guard caret.midX.isFinite, caret.minY.isFinite, caret.height.isFinite else {
                button.isHidden = true
                return
            }
            let size = EditorLineActionButton.size
            let gap: CGFloat = 8
            let topGuard = size / 2 + 4
            let bottomGuard = tv.bounds.height - size / 2 - 4

            // 光标矩形换算到可视坐标（横向一般不滚动，仍减 contentOffset 以防万一）。
            let caretTopY = caret.minY - tv.contentOffset.y
            let caretBottomY = caret.maxY - tv.contentOffset.y
            let caretCenterX = caret.midX - tv.contentOffset.x

            // 横向对齐光标、夹在左右缘内。
            let x = min(max(caretCenterX, size / 2 + 4), tv.bounds.width - size / 2 - 4)

            // 竖向优先放光标上方；上方越界（顶部/灵动岛）则翻到下方。
            var y = caretTopY - gap - size / 2
            if y < topGuard { y = caretBottomY + gap + size / 2 }
            y = min(max(y, topGuard), bottomGuard)

            // 仅当光标行整体滚出可视区（上方或下方）才隐藏。
            let lineVisible = caretBottomY > 0 && caretTopY < tv.bounds.height
            button.isHidden = !lineVisible
            if lineVisible { button.center = CGPoint(x: x, y: y) }
        }
    }
}
