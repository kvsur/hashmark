//
//  MarkdownEditingEngine.swift
//  MarkdownApp
//
//  编辑器规则门面：Coordinator 只认识这个入口，不依赖各条具体规则。
//

enum MarkdownEditingEngine {
    static func mutation(
        for edit: MarkdownProposedEdit,
        in context: MarkdownEditingContext
    ) -> MarkdownTextMutation? {
        MarkdownSmartInputEngine.mutation(for: edit, in: context)
    }

    static func mutation(
        for command: MarkdownEditorCommand,
        in context: MarkdownEditingContext
    ) -> MarkdownTextMutation? {
        MarkdownCommandEngine.mutation(for: command, in: context)
    }
}

