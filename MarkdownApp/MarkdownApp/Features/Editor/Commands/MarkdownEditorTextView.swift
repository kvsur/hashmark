//
//  MarkdownEditorTextView.swift
//  MarkdownApp
//
//  只承载硬件键盘命令发现；文本规则仍由 Coordinator → MarkdownEditingEngine 处理。
//

import UIKit

final class MarkdownEditorTextView: UITextView {
    var onEditorCommand: ((MarkdownEditorCommand) -> Void)?

    override var keyCommands: [UIKeyCommand]? {
        var commands = super.keyCommands ?? []
        commands += [
            command("Bold", input: "b", modifiers: .command, action: #selector(toggleBold)),
            command("Italic", input: "i", modifiers: .command, action: #selector(toggleItalic)),
            command("Strikethrough", input: "u", modifiers: [.command, .alternate], action: #selector(toggleStrikethrough)),
            command("Link", input: "k", modifiers: .command, action: #selector(toggleLink)),
            command("Inline Code", input: "j", modifiers: .command, action: #selector(toggleInlineCode)),
            command("Bullet List", input: "l", modifiers: .command, action: #selector(toggleBulletList)),
            command("Numbered List", input: "l", modifiers: [.command, .shift], action: #selector(toggleNumberedList)),
            command("Task List", input: "l", modifiers: [.command, .alternate], action: #selector(toggleTaskList)),
            command("Indent", input: "\t", modifiers: [], action: #selector(indentSelection)),
            command("Outdent", input: "\t", modifiers: .shift, action: #selector(outdentSelection)),
            command("Move Line Up", input: UIKeyCommand.inputUpArrow,
                    modifiers: [.command, .alternate], action: #selector(moveLinesUp)),
            command("Move Line Down", input: UIKeyCommand.inputDownArrow,
                    modifiers: [.command, .alternate], action: #selector(moveLinesDown))
        ]
        for level in MarkdownHeadingLevel.allCases {
            let headingTitle = String(
                format: String(localized: "Heading Level %lld"),
                locale: .current,
                Int64(level.rawValue)
            )
            commands.append(command(
                headingTitle,
                input: String(level.rawValue),
                modifiers: .command,
                action: headingSelector(level)
            ))
        }
        return commands
    }

    private func command(
        _ titleKey: String.LocalizationValue,
        input: String,
        modifiers: UIKeyModifierFlags,
        action: Selector
    ) -> UIKeyCommand {
        let title = String(localized: titleKey)
        let result = UIKeyCommand(title: title, action: action, input: input, modifierFlags: modifiers)
        result.discoverabilityTitle = title
        return result
    }

    private func command(
        _ title: String,
        input: String,
        modifiers: UIKeyModifierFlags,
        action: Selector
    ) -> UIKeyCommand {
        let result = UIKeyCommand(title: title, action: action, input: input, modifierFlags: modifiers)
        result.discoverabilityTitle = title
        return result
    }

    private func headingSelector(_ level: MarkdownHeadingLevel) -> Selector {
        switch level {
        case .one: #selector(heading1)
        case .two: #selector(heading2)
        case .three: #selector(heading3)
        case .four: #selector(heading4)
        case .five: #selector(heading5)
        case .six: #selector(heading6)
        }
    }

    @objc private func toggleBold() { onEditorCommand?(.toggleInline(.bold)) }
    @objc private func toggleItalic() { onEditorCommand?(.toggleInline(.italic)) }
    @objc private func toggleStrikethrough() { onEditorCommand?(.toggleInline(.strikethrough)) }
    @objc private func toggleLink() { onEditorCommand?(.toggleInline(.link)) }
    @objc private func toggleInlineCode() { onEditorCommand?(.toggleInline(.inlineCode)) }
    @objc private func toggleBulletList() { onEditorCommand?(.toggleBlock(.unorderedList)) }
    @objc private func toggleNumberedList() { onEditorCommand?(.toggleBlock(.orderedList)) }
    @objc private func toggleTaskList() { onEditorCommand?(.toggleBlock(.taskList)) }
    @objc private func indentSelection() { onEditorCommand?(.indent) }
    @objc private func outdentSelection() { onEditorCommand?(.outdent) }
    @objc private func moveLinesUp() { onEditorCommand?(.moveLines(.up)) }
    @objc private func moveLinesDown() { onEditorCommand?(.moveLines(.down)) }
    @objc private func heading1() { onEditorCommand?(.toggleBlock(.heading(.one))) }
    @objc private func heading2() { onEditorCommand?(.toggleBlock(.heading(.two))) }
    @objc private func heading3() { onEditorCommand?(.toggleBlock(.heading(.three))) }
    @objc private func heading4() { onEditorCommand?(.toggleBlock(.heading(.four))) }
    @objc private func heading5() { onEditorCommand?(.toggleBlock(.heading(.five))) }
    @objc private func heading6() { onEditorCommand?(.toggleBlock(.heading(.six))) }
}
