//
//  MarkdownEditorCommand.swift
//  MarkdownApp
//
//  与具体按钮、菜单、快捷键无关的编辑命令。iPhone 工具栏、iPad 快捷栏和硬件键盘
//  最终都发出这些命令，保证不同入口得到同一份 Markdown 变换。
//

import Foundation

enum MarkdownEditorCommand: Equatable {
    case toggleInline(MarkdownInlineStyle)
    case toggleBlock(MarkdownBlockStyle)
    case indent
    case outdent
    case moveLines(MarkdownLineMoveDirection)
}

enum MarkdownInlineStyle: Equatable {
    case bold
    case italic
    case strikethrough
    case inlineCode
    case link
}

enum MarkdownBlockStyle: Equatable {
    case heading(MarkdownHeadingLevel)
    case blockquote
    case unorderedList
    case orderedList
    case taskList
    case fencedCode
}

enum MarkdownHeadingLevel: Int, CaseIterable, Equatable {
    case one = 1
    case two
    case three
    case four
    case five
    case six
}

enum MarkdownLineMoveDirection: Equatable {
    case up
    case down
}

