import Foundation

private var failures: [String] = []

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { failures.append(message) }
}

private func applying(_ mutation: MarkdownTextMutation?, to source: String) -> (String, NSRange)? {
    guard let mutation else { return nil }
    let context = MarkdownEditingContext(text: source, selectedRange: NSRange(location: 0, length: 0))
    guard mutation.isValid(in: context) else { return nil }
    return ((source as NSString).replacingCharacters(in: mutation.range, with: mutation.replacementText),
            mutation.selectedRangeAfter)
}

private func smartEdit(_ source: String, range: NSRange, replacement: String) -> (String, NSRange)? {
    let context = MarkdownEditingContext(text: source, selectedRange: range)
    let mutation = MarkdownEditingEngine.mutation(
        for: MarkdownProposedEdit(range: range, replacementText: replacement),
        in: context
    )
    return applying(mutation, to: source)
}

private func command(_ source: String, selection: NSRange, _ command: MarkdownEditorCommand) -> (String, NSRange)? {
    let context = MarkdownEditingContext(text: source, selectedRange: selection)
    return applying(MarkdownEditingEngine.mutation(for: command, in: context), to: source)
}

@main
enum MarkdownEditingEngineTests {
static func main() {
let emojiContext = MarkdownEditingContext(text: "a😀b", selectedRange: NSRange(location: 1, length: 2))
expect(emojiContext.utf16Length == 4, "emoji 应以 UTF-16 长度 2 计")
expect(emojiContext.hasValidRanges, "合法 emoji 选区应通过")
expect(!emojiContext.contains(NSRange(location: 4, length: 1)), "越界 range 应被拒绝")

expect(smartEdit("1. one", range: NSRange(location: 6, length: 0), replacement: "\n")?.0 == "1. one\n2. ",
       "有序列表应递增")
expect(smartEdit("- one", range: NSRange(location: 5, length: 0), replacement: "\n")?.0 == "- one\n- ",
       "无序列表应续写同 marker")
expect(smartEdit("- [x] done", range: NSRange(location: 10, length: 0), replacement: "\n")?.0 == "- [x] done\n- [ ] ",
       "任务列表新项应重置为未完成")
expect(smartEdit("1. ", range: NSRange(location: 3, length: 0), replacement: "\n")?.0 == "",
       "空顶层列表应退出")
expect(smartEdit("    - ", range: NSRange(location: 6, length: 0), replacement: "\n")?.0 == "- ",
       "空嵌套列表应先 outdent")
expect(smartEdit("> quote", range: NSRange(location: 7, length: 0), replacement: "\n")?.0 == "> quote\n> ",
       "引用应续写 prefix")
expect(smartEdit("```\n  code", range: NSRange(location: 10, length: 0), replacement: "\n")?.0 == "```\n  code\n  ",
       "代码围栏内应保留缩进")

let linkSource = "OpenAI"
expect(smartEdit(linkSource, range: NSRange(location: 0, length: 6), replacement: "https://openai.com")?.0
       == "[OpenAI](https://openai.com)", "选区粘贴 URL 应生成链接")
expect(smartEdit("", range: NSRange(location: 0, length: 0), replacement: "[")?.0 == "[]",
       "左方括号应保守配对")

expect(command("hello", selection: NSRange(location: 0, length: 5), .toggleInline(.bold))?.0 == "**hello**",
       "bold 应包裹选区")
expect(command("**hello**", selection: NSRange(location: 0, length: 9), .toggleInline(.bold))?.0 == "hello",
       "bold 再次执行应去除 marker")
expect(command("one\ntwo", selection: NSRange(location: 0, length: 7), .toggleBlock(.unorderedList))?.0 == "- one\n- two",
       "多行应统一切换为列表")
expect(command("one\ntwo", selection: NSRange(location: 0, length: 7), .indent)?.0 == "    one\n    two",
       "多行 indent 应一次变换")
expect(command("one\ntwo\n", selection: NSRange(location: 4, length: 3), .moveLines(.up))?.0 == "two\none\n",
       "选中行应可向上移动")

let emptyBlockCases: [(MarkdownBlockStyle, String)] = [
    (.unorderedList, "- "),
    (.orderedList, "1. "),
    (.taskList, "- [ ] "),
    (.blockquote, "> "),
    (.heading(.two), "## ")
]
for (style, marker) in emptyBlockCases {
    let inserted = command("", selection: NSRange(location: 0, length: 0), .toggleBlock(style))
    expect(inserted?.0 == marker, "空行应插入 \(marker) 标记")
    let removed = command(marker, selection: NSRange(location: marker.utf16.count, length: 0), .toggleBlock(style))
    expect(removed?.0 == "", "再次点击应移除 \(marker) 标记")
}
expect(
    command("paragraph\n", selection: NSRange(location: 10, length: 0), .toggleBlock(.unorderedList))?.0
        == "paragraph\n- ",
    "段落后的空行应可插入块标记"
)
expect(command("", selection: NSRange(location: 0, length: 0), .indent)?.0 == "    ",
       "空行 indent 应插入一级缩进")
expect(command("", selection: NSRange(location: 0, length: 0), .outdent) == nil,
       "没有缩进的空行 outdent 应保持 no-op")

let largeDocument = String(repeating: "- item in a large document\n", count: 4_000) + "1. last"
let benchmarkStart = Date()
let largeResult = smartEdit(
    largeDocument,
    range: NSRange(location: largeDocument.utf16.count, length: 0),
    replacement: "\n"
)
let benchmarkDuration = Date().timeIntervalSince(benchmarkStart)
expect(largeResult?.0.hasSuffix("1. last\n2. ") == true, "大文档末尾仍应正确续写")
expect(benchmarkDuration < 0.1, "100k 字符局部规则不应执行全文重解析")

if failures.isEmpty {
    print("MarkdownEditingEngineTests: PASS")
} else {
    failures.forEach { print("FAIL: \($0)") }
    exit(1)
}
}
}
