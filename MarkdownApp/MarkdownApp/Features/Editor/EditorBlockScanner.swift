//
//  EditorBlockScanner.swift
//  MarkdownApp
//
//  轻量的「Markdown 源码 → 结构块」行级扫描器（纯逻辑，无 UIKit 依赖，便于单测）。
//  给编辑模式的「跟随光标行的一键选块」用：识别标题 / 代码块(fenced) / 表格 / 引用四类「独立块」，
//  产出每块在源码中的字符范围（NSRange），供 UITextView 定位标记与设置选区。
//
//  为什么自己写而不用现成解析器：预览走的是 web 端 markdown-it，Swift 侧没有块解析；
//  这里只需「块的边界与类型」，行级扫描足够、也最好控成本与可测性。范围用 NSRange 是刻意的——
//  UITextView 的选区/布局都以 UTF-16 计（NSString），与之对齐避免 emoji/组合字符处的偏移错位。
//
//  设计选择：「标题」块的选区取「整段 section」——标题行到下一个同级/更高级标题之前的全部正文
//  （遇代码块内的 # 不误判）。但标题不「消费」这些正文行：section 内的代码块/表格/引用仍各自出块，
//  于是同一段落在不同行上有不同粒度的标记（标题行选整段、代码行选代码块），互补而不冲突。
//  代码块/表格/引用则覆盖各自的完整多行范围。
//

import Foundation

/// 一个可被「一键选中」的结构块。
struct MarkdownBlock: Equatable {
    enum Kind: Equatable { case heading, codeFence, table, blockquote }
    let kind: Kind
    /// 块在源码中的完整字符范围（UTF-16 / NSString 计），用于设置 UITextView.selectedRange。
    let range: NSRange
}

enum EditorBlockScanner {

    /// 扫描源码，按文档顺序返回结构块。
    static func scan(_ source: String) -> [MarkdownBlock] {
        let lines = splitLines(source)
        guard !lines.isEmpty else { return [] }

        var blocks: [MarkdownBlock] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]

            // 1) 代码块（fenced）：``` 或 ~~~ 开栏 → 找同类收栏；未收则延伸到文末。
            if let fence = fenceMarker(line.content) {
                var j = i + 1
                while j < lines.count {
                    if let close = fenceMarker(lines[j].content), close == fence { break }
                    j += 1
                }
                let end = min(j, lines.count - 1)
                blocks.append(MarkdownBlock(kind: .codeFence, range: span(lines, i, end)))
                i = end + 1
                continue
            }

            // 2) 标题：选区取整段 section（标题行 → 下一个同级/更高级标题前）；但不消费正文，
            //    只推进一行，让 section 内的代码块/表格/引用仍各自被识别为独立块。
            if let level = headingLevel(line.content) {
                let end = sectionEndLine(lines, from: i, level: level)
                blocks.append(MarkdownBlock(kind: .heading, range: span(lines, i, end)))
                i += 1
                continue
            }

            // 3) 表格：当前行像表头（含 |、非空）且下一行是分隔行（|、-、:）→ 连续吃后续含 | 的行。
            if i + 1 < lines.count,
               looksLikeTableRow(line.content),
               isTableDelimiter(lines[i + 1].content) {
                var j = i + 1   // 至少含表头 + 分隔行
                while j + 1 < lines.count, looksLikeTableRow(lines[j + 1].content) { j += 1 }
                blocks.append(MarkdownBlock(kind: .table, range: span(lines, i, j)))
                i = j + 1
                continue
            }

            // 4) 引用：连续以 > 开头的行成一块。
            if isBlockquote(line.content) {
                var j = i
                while j + 1 < lines.count, isBlockquote(lines[j + 1].content) { j += 1 }
                blocks.append(MarkdownBlock(kind: .blockquote, range: span(lines, i, j)))
                i = j + 1
                continue
            }

            i += 1
        }
        return blocks
    }

    /// 给「跟随光标的块操作按钮」用：按光标所在**行**决定要选的最贴切单元——
    /// 1) 光标落在代码块 / 表格 / 引用内 → 选该块（叶子块，最具体）；
    /// 2) 光标正处在标题行 → 选该标题的整段 section；
    /// 3) 其余（普通段落）→ 选「当前段落」（以空行为界的连续非空行）。
    /// 之所以不简单地「取包含光标的块」：H1 的 section 往往覆盖全文，会让站在任何位置都误选整篇。
    static func enclosingSelection(at location: Int, in source: String) -> NSRange {
        let blocks = scan(source)
        // 1) 叶子块（非标题）按范围包含匹配；一个位置至多落在一个叶子块内。
        for block in blocks where block.kind != .heading {
            if location >= block.range.location,
               location <= block.range.location + block.range.length {
                return block.range
            }
        }
        // 2) 光标是否正处在某标题行上（而非只是落在它的 section 里）。
        let lines = splitLines(source)
        if let idx = lineIndex(lines, at: location), headingLevel(lines[idx].content) != nil {
            let lineStart = lines[idx].range.location
            if let heading = blocks.first(where: { $0.kind == .heading && $0.range.location == lineStart }) {
                return heading.range
            }
        }
        // 3) 当前段落。
        return paragraphRange(lines, at: location)
    }

    /// 以空行为界的「当前段落」范围。光标恰在空行上则返回该空行（length 可能为 0）。
    private static func paragraphRange(_ lines: [Line], at location: Int) -> NSRange {
        guard !lines.isEmpty else { return NSRange(location: max(location, 0), length: 0) }
        let cur = lineIndex(lines, at: location) ?? (lines.count - 1)
        let isBlank: (Int) -> Bool = { lines[$0].content.trimmingCharacters(in: .whitespaces).isEmpty }
        // 段落边界：空行，或相邻行本身是结构块起始（标题/围栏/引用），都不并入当前段落。
        let isBoundary: (Int) -> Bool = {
            let c = lines[$0].content
            return isBlank($0) || headingLevel(c) != nil || fenceMarker(c) != nil || isBlockquote(c)
        }
        if isBoundary(cur) { return lines[cur].range }
        var start = cur, end = cur
        while start - 1 >= 0, !isBoundary(start - 1) { start -= 1 }
        while end + 1 < lines.count, !isBoundary(end + 1) { end += 1 }
        return span(lines, start, end)
    }

    /// 光标位置所在行的下标。
    private static func lineIndex(_ lines: [Line], at location: Int) -> Int? {
        for (i, line) in lines.enumerated() {
            if location <= line.range.location + line.range.length { return i }
        }
        return lines.isEmpty ? nil : lines.count - 1
    }

    // MARK: - 行拆分

    private struct Line { let content: String; let range: NSRange }

    /// 按行拆分，保留每行「不含换行符」的内容与其在源码中的 NSRange。
    private static func splitLines(_ source: String) -> [Line] {
        let ns = source as NSString
        var lines: [Line] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length),
                               options: [.byLines, .substringNotRequired]) { _, substringRange, _, _ in
            let content = ns.substring(with: substringRange)
            lines.append(Line(content: content, range: substringRange))
        }
        return lines
    }

    /// 从第 start 行到第 end 行（含）的合并范围，只覆盖内容、不含末行之后的换行符。
    private static func span(_ lines: [Line], _ start: Int, _ end: Int) -> NSRange {
        let a = lines[start].range
        let b = lines[end].range
        return NSRange(location: a.location, length: (b.location + b.length) - a.location)
    }

    // MARK: - 单行分类（纯字符判断，避免正则脆弱性）

    /// 去掉至多 3 个前导空格后的剩余字符串（Markdown 允许块级元素带 0–3 个前导空格缩进）。
    private static func trimmedLeading(_ s: String) -> Substring {
        var idx = s.startIndex
        var spaces = 0
        while idx < s.endIndex, s[idx] == " ", spaces < 3 {
            idx = s.index(after: idx); spaces += 1
        }
        return s[idx...]
    }

    /// 代码栏标记：返回 "```" 或 "~~~"（取首字符类别），非围栏行返回 nil。
    private static func fenceMarker(_ line: String) -> Character? {
        let t = trimmedLeading(line)
        if t.hasPrefix("```") { return "`" }
        if t.hasPrefix("~~~") { return "~" }
        return nil
    }

    /// ATX 标题级别（1–6），非标题返回 nil。# 后须是空白或行尾，排除 #tag 之类。
    private static func headingLevel(_ line: String) -> Int? {
        let t = trimmedLeading(line)
        var count = 0
        var idx = t.startIndex
        while idx < t.endIndex, t[idx] == "#" { count += 1; idx = t.index(after: idx) }
        guard count >= 1, count <= 6 else { return nil }
        guard idx == t.endIndex || t[idx] == " " || t[idx] == "\t" else { return nil }
        return count
    }

    /// 从标题所在行 `from` 起，找 section 的最后一行（含）：下一个级别 ≤ level 的标题之前。
    /// 扫描时跟踪代码围栏，避免把代码块内的 # 当标题；末尾的空行从 section 中剔除，让选区更干净。
    private static func sectionEndLine(_ lines: [Line], from: Int, level: Int) -> Int {
        var fence: Character?
        var end = lines.count - 1
        var j = from + 1
        while j < lines.count {
            let content = lines[j].content
            if let marker = fenceMarker(content) {
                if fence == nil { fence = marker }
                else if fence == marker { fence = nil }
            } else if fence == nil, let lv = headingLevel(content), lv <= level {
                end = j - 1
                break
            }
            j += 1
        }
        // 剔除 section 末尾的空行（但至少保留标题行本身）。
        while end > from,
              lines[end].content.trimmingCharacters(in: .whitespaces).isEmpty {
            end -= 1
        }
        return end
    }

    private static func isBlockquote(_ line: String) -> Bool {
        trimmedLeading(line).hasPrefix(">")
    }

    /// 看起来像表格数据行：非空且含竖线。
    private static func looksLikeTableRow(_ line: String) -> Bool {
        let t = trimmedLeading(line)
        return !t.trimmingCharacters(in: .whitespaces).isEmpty && t.contains("|" as Character)
    }

    /// 表格分隔行：只由 | - : 空白组成，且至少各含一个 | 和 -（借此把它和 `---` 分割线区分开）。
    private static func isTableDelimiter(_ line: String) -> Bool {
        let t = trimmedLeading(line)
        guard !t.isEmpty else { return false }
        var hasPipe = false, hasDash = false
        for ch in t {
            switch ch {
            case "|": hasPipe = true
            case "-": hasDash = true
            case ":", " ", "\t": break
            default: return false
            }
        }
        return hasPipe && hasDash
    }
}
