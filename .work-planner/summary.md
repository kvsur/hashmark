# Plan Summary — AI 写作（流式生成 + 边收边渲染 + 预览应用）

## Goal
把 App 从「Markdown 预览/编辑器」升级为「带 AI 写作助手」的工具：用户用 prompt（预设或自定义）驱动 AI，**流式**生成 Markdown，边收边在 WebView 里渲染预览，满意则应用到文档、放弃则丢弃。
从（From）：AI 相关只有配置（AIConfig/AIConfigStore：BaseURL/Model/APIKey/响应格式 ChatGPT|Claude）与占位按钮 AIAssistButton。
到（To）：端到端可用的 AI 写作——首页「一键生成整篇」+ 编辑器内「续写/润色/整理/自定义」，均流式渲染、预览确认后应用。

## Scope
- In（本期）：
  - AI 网络层：流式 client，兼容 ChatGPT（OpenAI 式 /chat/completions）与 Claude（Anthropic /messages）两种 SSE 格式；鉴权、错误、取消。
  - 动作/提示词：续写、润色/改写、整理格式、自定义指令——本质都是「prompt 模板 + 上下文注入策略（全文/选中/无）」。
  - 流式渲染：往 WebView 增量推 delta，marked.js 节流重渲染 + 自动滚底（性能关键）。
  - AI 会话 UI：prompt 半屏 modal → 一开始返回立即转全屏；loading/streaming/done/error 全状态；取消；接受 / close（close 前二次确认）。
  - 首页「一键开启 AI 写作」：**大号**醒目入口 → 输入 prompt → 生成整篇 → 接受则新建文档进入。
  - 编辑器/预览内 AI：AIAssistButton 选动作 → 会话 → 预览确认后应用（插入/替换）到当前文档。
- Out / 后续：
  - 翻译/总结等更多预设（可用「自定义指令」先覆盖）。
  - AI 会话内的可编辑 Tab（本期只预览；接受后落到编辑器再改）。
  - 多轮对话 / 上下文记忆 / 历史记录。
  - 本地模型、图片多模态。

## Constraints / Coexistence
- 遵循 CLAUDE.md：功能分层（新代码进 Features/AI + Models）、文案禁 emoji、图标用 SF Symbols、DRY、视图轻/逻辑外移、版本差异收敛封装层。
- 最低 iOS 18；SwiftUI + 现有 WebPreviewView（marked.js 本地资源）复用。
- APIKey/配置来自 AIConfigStore（Library/Application Support），HTTPS。
- AIConfig 任一项（baseURL/model/apiKey）未配置即不得进入 AI 模式：共享 AIConfigGate 先提示、再跳转到 AI 配置页；所有 AI 入口统一走此门槛，不静默失败。
- 本机仅 CommandLineTools 无完整 Xcode，编译/运行验证由用户在 Xcode Run；SourceKit 跨文件报错为索引噪声。

## Definition of Done
- 首页大号 AI 入口 → 半屏输入 prompt → 开始返回即转全屏 → 流式边渲染 → 接受生成新文档 / close（二次确认）丢弃。
- 编辑器内 AI（续写/润色/整理/自定义）流式生成、预览确认后应用到当前文档。
- ChatGPT 与 Claude 两种响应格式都能流式跑通。
- loading/error/取消/空 prompt/无配置 等边界都有明确反馈、不崩。

## Key Decisions (locked)
| Decision | Choice | Why |
|---|---|---|
| 动作模型 | 预设=prompt 模板 + 上下文策略；含自定义自由 prompt | 用户洞察：一切皆 prompt |
| 输出 | 必须流式 + 边收边渲染 | 用户明确要求，体验核心 |
| 流式渲染 | WebView 增量推 delta + marked.js 节流重渲染 + 自动滚底 | 兼顾实时性与性能 |
| 结果应用 | 先弹层预览（渲染态），确认后应用；本期不加编辑 Tab | 用户要预览；接受后落编辑器再改 |
| 首页入口 | 大号入口 → prompt 生成整篇 → 接受新建文档 | 用户指定，含「按钮做大」 |
| 输入交互 | prompt 半屏 modal → 开始返回立即全屏 | 用户指定的交互细节 |
| 放弃 | close 前二次确认（有已生成内容时） | 用户指定 |
| 双格式 | ChatGPT(OpenAI) 与 Claude(Anthropic) 均支持流式 | AIConfig.responseFormat 已有 |
| 无配置 | 任一字段空即拦截：先提示、再跳 AI 配置页（共享 AIConfigGate） | 不能静默失败，所有入口统一 |
