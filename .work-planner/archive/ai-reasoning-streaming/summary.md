# Plan Summary

## Goal

把 AI 写作当前“请求发出后只显示居中加载器、等正文首 token 才进入预览”的黑箱等待，升级为供应商无关的双通道流式体验：上游若返回可展示的 thinking/reasoning 摘要，则在生成期间实时呈现；正文开始后让推理轨迹退居次级、最终 Markdown 成为视觉与数据主角。若上游不返回 reasoning，现有生成链路仍正常工作。

## Scope

- In:
  - 为 reasoning、正文和工具调用建立互不污染的统一流式事件模型。
  - 仅支持两类主流生态：OpenAI-compatible Chat Completions 与 Anthropic-compatible Messages。
  - 解析并展示供应商实际返回的 reasoning/thinking 摘要；不伪造、不从正文标签猜测为原始思维链。
  - 保留 Claude thinking block/signature 等继续工具调用所需的传输元数据，但不把它们暴露为 Markdown 正文。
  - 为 AI 写作全屏生成态设计可滚动、可收拢、支持无 reasoning 降级的原生 SwiftUI UI。
  - 覆盖停止、重试、精修、重新生成、反问工具、流中断、空正文和多轮状态清理。
  - 新增文案补齐简中、英、繁中、日、韩、德、俄，并完成 VoiceOver、Dynamic Type、Reduce Motion、深浅色和 iPhone/iPad 验收。
- Out:
  - 展示或声称展示供应商未返回的原始 chain-of-thought。
  - 为 DeepSeek、Qwen、Gemini、GLM、Kimi、Doubao、Step 等新增独立配置类型或客户端；首轮只覆盖 App 现有协议边界及兼容字段。
  - 增加 reasoning 深度、token budget、effort 等高级调参 UI；首轮只消费安全可用的返回内容。
  - 保存 reasoning 到 Markdown 文件、接受结果、剪贴板或文档历史。
  - 改造普通 Markdown Preview、编辑器或文件浏览器。

## Constraints / Coexistence

- 当前工作区已有大量未提交代码改动；本任务必须保留并基于现状增量工作，不清理、不回滚无关改动。
- 设置只展示 `OpenAI` 与 `Anthropic`；内部保留 `.chatGPT`/`.claude` raw value 以兼容已有配置，实验性的 `openAIResponses` 配置迁回 OpenAI 类。
- reasoning 只是一条显示通道；`AIWritingSession.text/committedText/finalText` 的正文语义保持不变，`onAccept` 永远只收到最终 Markdown。
- 任意端点可能是兼容代理。未知字段应忽略，reasoning 缺失不得报错；请求参数不被上游支持时不得在已产出内容后自动重放。
- 供应商返回的可见内容应称为“推理摘要/Reasoning”，不得暗示是完整内部思维链。
- UI 使用系统语义颜色、系统字体与 SF Symbols；现有 `Theme.aiAccent` 是品牌锚点，新增视觉 token 收敛到 DesignSystem。

## Definition of Done

1. OpenAI-compatible 与 Anthropic-compatible fixture 可重放为有序的 `.reasoning`、`.text`、`.toolCall`/完成事件，reasoning 永不混入正文。
2. OpenAI-compatible Chat Completions 能容忍并解析计划锁定的常见 reasoning 增量字段；无这些字段时行为与当前一致。
3. Anthropic Messages 可处理 `thinking_delta`、`signature_delta`、`text_delta` 与工具调用；需要回填工具结果时能原样保留协议要求的 thinking transport block。
4. 等待首事件、仅 reasoning、reasoning→正文、无 reasoning→正文、仅 reasoning 后结束、流中断和用户 Stop 均有确定的会话状态与 UI。
5. reasoning 生成中实时可读；正文开始后推理区域自动收拢但可手动展开；最终 Markdown 始终获得主要空间并保留现有贴底/跳到最新行为。
6. reasoning 不进入接受结果、精修底稿或文档保存；重新生成/精修开启新一轮时旧 reasoning 不串入。
7. 新增 UI 文案完成七语言本地化；VoiceOver、Dynamic Type、Reduce Motion、深浅色、iPhone/iPad 通过验收。
8. 解析器/会话测试、Debug/Release 构建、现有 AI 反问/附件/停止/重试/精修/接受回归通过。

## Context & References

| id | Source | Location | What it's for |
|---|---|---|---|
| C1 | 用户原始需求 | context/ai-reasoning-stream-requirements.md | 产品目标与工程约束 |
| C2 | 当前 AI Writing 加载态截图 | context/ai-writing-loading-reference.png | 记录“大片空白 + 居中加载器”的 from-state，不是目标稿 |
| C3 | 用户提供的 LLM Thinking API 调研 | context/llm-thinking-api-research.md | 多供应商字段线索；属于时点快照，实施前以官方文档和 fixture 复核 |
| C4 | 智谱 OpenAI API 兼容文档 | https://docs.bigmodel.cn/cn/guide/develop/openai/introduction | 验证主流兼容面为 `/chat/completions` 与 `reasoning_content` |
| C5 | 智谱 Claude API 兼容文档 | https://docs.bigmodel.cn/cn/guide/develop/claude/introduction | 验证 Anthropic SDK `/v1/messages` 兼容面 |
| C6 | Claude Thinking 官方文档 | https://platform.claude.com/docs/en/build-with-claude/thinking | thinking block、display、streaming、signature 与 tool-use 约束 |
| C7 | 当前共享 AI/SSE 层 | MarkdownApp/MarkdownApp/Models/AIClient.swift | 协议、SSE pump、工具降级与端点拼接边界 |
| C8 | 当前 OpenAI-compatible 客户端 | MarkdownApp/MarkdownApp/Models/ChatGPTClient.swift | `/chat/completions` 请求和 delta/tool parser |
| C9 | 当前 Claude 客户端 | MarkdownApp/MarkdownApp/Models/ClaudeClient.swift | Messages 请求、content block 与 tool parser |
| C10 | 当前消息和工具模型 | MarkdownApp/MarkdownApp/Models/AIMessage.swift；MarkdownApp/MarkdownApp/Models/AITool.swift | 中立消息、工具调用、AIStreamEvent 扩展点 |
| C11 | 当前 AI 会话状态机 | MarkdownApp/MarkdownApp/Features/AI/AIWritingSession.swift | reasoning 生命周期、正文隔离与 stop/retry/refine 入口 |
| C12 | 当前 AI 生成 UI | MarkdownApp/MarkdownApp/Features/AI/AIWritingView.swift；MarkdownApp/MarkdownApp/Features/AI/AIStreamingPreview.swift | 新推理轨迹组件与 Markdown 预览的组合边界 |
| C13 | 当前设计 token | MarkdownApp/MarkdownApp/DesignSystem/Theme.swift | 复用 AI accent、语义颜色与统一 token |
| C14 | AI 配置模型与编辑页 | MarkdownApp/MarkdownApp/Models/AIConfig.swift；MarkdownApp/MarkdownApp/Features/Settings/AIConfigEditorView.swift | OpenAI/Anthropic 两类选项与旧配置迁移入口 |

## Assumptions and Open Questions

| Item | Status | Why it matters | Resolution point |
|---|---|---|---|
| Chat Completions 兼容 reasoning 字段集合 | open | 聚合平台字段没有统一标准，过宽解析会误收正文 | S1.2 以匿名 fixture 明确白名单 |
| Claude 是否主动附加 thinking/display 请求参数 | assumed: 首轮不强制 | 任意模型/代理能力不可可靠推断，强制参数可能 400 或改变成本 | S1.3 对照当前模型矩阵；只在可无损协商时放开 |
| 两类主流协议边界 | confirmed | 智谱等主流供应商同时提供 OpenAI Chat Completions 与 Anthropic Messages 兼容入口，不以 `/responses` 作为通用兼容面 | S2 收口为两个配置类型 |
| reasoning 展示内容长度 | assumed: 本轮内完整保留 | 用户需要看生成过程；通过限高滚动而非截断控制布局 | S4 性能和可读性验收 |
| 正文开始后的默认状态 | assumed: 自动收拢，可手动展开 | 避免 reasoning 抢正文空间，同时保留可追溯性 | S4 视觉验收 |

## Key Decisions (locked)

| Decision | Choice | Why |
|---|---|---|
| 数据隔离 | reasoning 与 answer 是独立事件、独立缓冲、独立渲染 | 防止思考内容写入 Markdown 或污染精修底稿 |
| 内容真实性 | 只展示上游明确返回的可见摘要/字段 | 不伪造、不过度声称 chain-of-thought |
| 协议兼容性 | 设置仅展示 `OpenAI` 与 `Anthropic`，分别映射 Chat Completions 与 Messages | 覆盖主流 SDK 兼容生态，避免把 OpenAI 专有 Responses API 误当成第三类通用协议 |
| Claude 连续性 | 可见摘要与 opaque transport 元数据分离保存 | UI 不需要 signature，但工具回填必须协议正确 |
| UI 层级 | reasoning 生成时展开，正文到达后自动收拢，用户可重新展开 | 把等待变得可理解，又不让过程压过结果 |
| 视觉签名 | 一条沿左侧推进的“推理轨迹线”，其余控件保持克制原生 | 对应写作草稿的边注感，不做通用聊天气泡/卡片 |
