//
//  EditorKeyboardBar.swift
//  MarkdownApp
//
//  iPhone/iPad 软件键盘上方的横向命令栏。按钮只发送统一命令，不实现 Markdown 变换。
//

import UIKit

final class EditorKeyboardBar: UIInputView {
    var onCommand: ((MarkdownEditorCommand) -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onDismissKeyboard: (() -> Void)?

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 48), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)

        let divider = UIView()
        divider.backgroundColor = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(divider)

        let dismiss = button(systemName: "keyboard.chevron.compact.down", label: "Hide Keyboard")
        dismiss.addAction(UIAction { [weak self] _ in self?.onDismissKeyboard?() }, for: .touchUpInside)
        dismiss.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dismiss)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        let undo = button(systemName: "arrow.uturn.backward", label: "Undo")
        undo.addAction(UIAction { [weak self] _ in self?.onUndo?() }, for: .touchUpInside)
        stack.addArrangedSubview(undo)
        let redo = button(systemName: "arrow.uturn.forward", label: "Redo")
        redo.addAction(UIAction { [weak self] _ in self?.onRedo?() }, for: .touchUpInside)
        stack.addArrangedSubview(redo)
        stack.addArrangedSubview(headingButton())
        addButton("bold", label: "Bold", command: .toggleInline(.bold), to: stack)
        addButton("italic", label: "Italic", command: .toggleInline(.italic), to: stack)
        addButton("strikethrough", label: "Strikethrough", command: .toggleInline(.strikethrough), to: stack)
        addButton("link", label: "Link", command: .toggleInline(.link), to: stack)
        addButton("chevron.left.forwardslash.chevron.right", label: "Inline Code", command: .toggleInline(.inlineCode), to: stack)
        addButton("list.bullet", label: "Bullet List", command: .toggleBlock(.unorderedList), to: stack)
        addButton("list.number", label: "Numbered List", command: .toggleBlock(.orderedList), to: stack)
        addButton("checklist", label: "Task List", command: .toggleBlock(.taskList), to: stack)
        addButton("text.quote", label: "Blockquote", command: .toggleBlock(.blockquote), to: stack)
        addButton("increase.indent", label: "Indent", command: .indent, to: stack)
        addButton("decrease.indent", label: "Outdent", command: .outdent, to: stack)
        addButton("curlybraces", label: "Code Block", command: .toggleBlock(.fencedCode), to: stack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: divider.leadingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            divider.trailingAnchor.constraint(equalTo: dismiss.leadingAnchor, constant: -4),
            divider.centerYAnchor.constraint(equalTo: centerYAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.heightAnchor.constraint(equalToConstant: 24),
            dismiss.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            dismiss.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
        ])
    }

    private func headingButton() -> UIButton {
        let result = button(systemName: "textformat.size", label: "Heading")
        result.showsMenuAsPrimaryAction = true
        result.menu = UIMenu(children: MarkdownHeadingLevel.allCases.map { level in
            let title = String(
                format: String(localized: "Heading Level %lld"),
                locale: .current,
                Int64(level.rawValue)
            )
            return UIAction(title: title) { [weak self] _ in
                self?.onCommand?(.toggleBlock(.heading(level)))
            }
        })
        return result
    }

    private func addButton(
        _ systemName: String,
        label: String.LocalizationValue,
        command: MarkdownEditorCommand,
        to stack: UIStackView
    ) {
        let result = button(systemName: systemName, label: label)
        result.addAction(UIAction { [weak self] _ in self?.onCommand?(command) }, for: .touchUpInside)
        stack.addArrangedSubview(result)
    }

    private func button(systemName: String, label: String.LocalizationValue) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: systemName)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
        let result = UIButton(configuration: configuration)
        result.accessibilityLabel = String(localized: label)
        result.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        result.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        return result
    }
}
