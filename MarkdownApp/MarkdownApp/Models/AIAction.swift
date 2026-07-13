//
//  AIAction.swift
//  MarkdownApp
//
//  AI 写作动作预设。用户洞察：一切皆 prompt——预设只是「systemPrompt + 上下文策略」的封装，
//  custom 则完全放开由用户自由输入。把「怎么组装请求消息」收敛在这里，UI 只管选动作/填 prompt。
//

import Foundation

enum AIAction: String, CaseIterable, Identifiable {
    case continueWriting   // 续写
    case polish            // 润色/改写
    case format            // 整理格式
    case custom            // 自定义指令（也用于首页「生成整篇」）

    var id: String { rawValue }

    var label: String {
        switch self {
        case .continueWriting: "续写"
        case .polish: "润色改写"
        case .format: "整理格式"
        case .custom: "自由创作"
        }
    }

    /// 选择器用图标（S6）。
    var systemImage: String {
        switch self {
        case .continueWriting: "text.append"
        case .polish: "wand.and.stars"
        case .format: "text.alignleft"
        case .custom: "sparkles"
        }
    }

    /// 是否必须有文档上下文：续写/润色/整理作用于已有内容；自定义可无（如首页新建）。
    var requiresContext: Bool { self != .custom }

    /// 在编辑器内接受结果时如何应用（S6）。
    /// 续写/自定义=追加到文末（不破坏原文，安全）；润色/整理=替换全文。
    enum ApplyMode { case append, replace }
    var editorApplyMode: ApplyMode {
        switch self {
        case .continueWriting, .custom: .append
        case .polish, .format: .replace
        }
    }

    /// 所有动作共用的「输出纪律」：约束模型别加寒暄前言、别把整篇塞进代码块、别擅自换语言。
    /// 抽成常量复用，避免四段 prompt 各写一遍（DRY）。
    private static let outputContract = """
    输出要求：
    - 直接输出正文，不要"好的""以下是"之类的开场白，也不要结尾的说明或总结。
    - 不要用 ``` 代码块把整篇内容包起来（正文中本就属于代码的片段除外）。
    - 与原文、用户输入保持同一种语言，不要擅自翻译或切换语言。
    - 只使用标准 Markdown 语法，保证在预览中能正确渲染。
    - 不要滥用 emoji：除非用户明确要求，标题、列表项、小标题 不是特殊情况 不加 emoji 点缀，正文也克制使用。
    - 避免"AI 腔"：不写空洞的套话与排比、不给每段硬凑加粗小标题、不在结尾强行升华或总结拔高；
      像专业作者那样，用具体、克制、自然的语言把事情说清楚。
    """

    /// 各动作的角色设定与做法；最终发送时会统一追加 `outputContract`。
    private var role: String {
        switch self {
        case .continueWriting:
            """
            你是一位资深写作者，正与用户接力完成同一篇 Markdown 文档。
            先揣摩已有内容的主题、语气、人称与详略节奏，再自然地承接着往下写，让新旧文字读来出自同一人之手。
            - 只写"接下来"的内容，绝不重复或改写已有段落。
            - 顺着上文的思路推进，不要另起炉灶或生硬转折。
            - 沿用原文的 Markdown 风格（标题层级、列表与强调样式等）。
            """
        case .polish:
            """
            你是一位严谨的文字编辑，负责润色用户提供的 Markdown。
            在完全保留原意与事实的前提下，让表达更准确通顺、更有节奏：删去啰嗦与重复、理顺逻辑、统一术语与语气。
            - 这是润色而非重写：不增删观点、不改变作者的立场与整体风格。
            - 保留原有的 Markdown 结构（标题、列表、代码、链接、表格等）。
            - 输出润色后的完整内容，而非改动清单。
            """
        case .format:
            """
            你是一位一丝不苟的 Markdown 排版师，只调整格式、绝不改动文字含义。
            逐项规范：标题层级是否连贯、列表与缩进是否统一、代码块是否标注语言、表格是否对齐、段落空行是否得当、中英文与数字间距、以及多余的空白。
            - 一个字都不增删、不改写正文，只动排版。
            - 输出整理后的完整 Markdown。
            """
        case .custom:
            """
            你是一位全能的 Markdown 写作助手。
            准确理解用户的要求并高质量地完成，产出结构清晰、层次分明、格式规范的 Markdown。
            - 优先满足用户明确提出的要求；要求未覆盖的细节，按对读者最有帮助的方式合理补全。
            """
        }
    }

    private var systemPrompt: String {
        role + "\n\n" + Self.outputContract
    }

    /// 组装用户消息：把文档上下文与用户 prompt 按动作语义拼起来。
    /// 文档内容一律用 <document> 标签圈定边界——与指令文字明确隔开，既避免混淆，也降低 prompt 注入风险。
    private func userContent(context: String?, prompt: String) -> String {
        let ctx = context?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let document = "<document>\n\(ctx)\n</document>"
        // 用户在文档之外的额外要求，单独标注、明确优先级，避免与文档正文混为一谈。
        let note = prompt.isEmpty ? "" : "\n\n用户的额外要求（请在完成上述任务时一并满足）：\n\(prompt)"
        switch self {
        case .continueWriting:
            return "以下是文档目前的内容：\n\(document)\n\n请紧接着最后一段，自然地续写下去。\(note)"
        case .polish:
            return "请润色下面这份文档：\n\(document)\(note)"
        case .format:
            return "请整理下面这份 Markdown 文档的排版：\n\(document)\(note)"
        case .custom:
            // 有上下文（编辑器内自定义）则带上参考；无上下文（首页从零生成）则只发用户要求。
            return ctx.isEmpty
                ? prompt
                : "以下是供你参考的文档内容：\n\(document)\n\n请按下面的要求处理：\n\(prompt)"
        }
    }

    /// 组装成发给 AIClient 的消息序列（system + user）。
    func messages(context: String?, prompt: String) -> [AIMessage] {
        let user = userContent(context: context, prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines))
        return [
            AIMessage(role: .system, content: systemPrompt),
            AIMessage(role: .user, content: user)
        ]
    }

    /// 发起前校验：返回非 nil 即不满足条件的原因（供 UI 提示、禁用开始按钮）。
    func validationError(context: String?, prompt: String) -> String? {
        let hasContext = !(context?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasPrompt = !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if requiresContext && !hasContext {
            return "当前文档没有内容，无法\(label)。"
        }
        if self == .custom && !hasPrompt {
            return "请先说说你想要什么。"
        }
        return nil
    }
}
