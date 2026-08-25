# Plan

## Product and design thesis

- Subject: 原生 iOS/iPadOS Markdown 写作助手。
- Audience: 正在等待长文本生成、需要知道系统仍在工作但不想阅读开发者日志的写作者。
- Single job: 把首个正文 token 前的黑箱等待变成可理解的“正在形成草稿”，并在答案到来时立刻把舞台让给 Markdown。

### Compact token system

- `AI Cobalt` `#1F61D1`: 现有 `Theme.aiAccent`，只用于活跃轨迹、焦点与少量状态文字。
- `Trace Violet` `#8C5CF5`: 取自现有 AI 渐变，只在运动中的轨迹端点短暂出现。
- `Trace Mist` `#DCE7FA`: 浅色模式轨迹底线/选中面；实现时映射为可适配对比度的语义 token。
- `Canvas Light` `#F2F2F7`: 对应系统 grouped background，不另造暖色卡片底。
- `Canvas Dark` `#1C1C1E`: 深色语义 surface 参考值。
- `Ink` `#1C1C1E`: 正文参考值，实际使用 `.primary/.secondary` 自动适配。

Typography uses native families for seven-language coverage: navigation/title uses SF Pro Display semibold; reasoning prose uses system serif body where the script supports it and system body fallback elsewhere; compact state/metadata uses SF Pro Rounded caption. Final Markdown continues using the existing preview typography.

### Layout explorations and chosen direction

Rejected generic direction: a centered sparkle, gradient card, or chat bubble would merely decorate waiting and still leave most of the screen inert. The chosen direction borrows from a writer's margin: reasoning is an open text column anchored by one thin progress trace, with no enclosing card.

During reasoning:

```text
┌──────────── AI Writing ────── Stop ┐
│                                    │
│  ●  Reasoning                      │
│  │  Reading the request…           │
│  │  Organizing the structure…      │
│  ◉  latest streamed line           │
│                                    │
└────────────────────────────────────┘
```

When answer text starts:

```text
┌──────────── AI Writing ────── Stop ┐
│  ›  Reasoning summary              │  collapsed by default
│  ────────────────────────────────  │
│  # Final Markdown answer…           │
│  …                                 │
│                         Latest ↓   │
└────────────────────────────────────┘
```

No reasoning returned: keep a compact semantic loading state until the first answer delta, then transition directly into the existing preview; never show an empty reasoning shell.

Signature: the left “reasoning trace” grows only while reasoning deltas arrive, then resolves into a static hairline. With Reduce Motion it changes state without traveling animation. This is the single visual risk; no extra glow, floating orb, or repeated gradient decoration is added.

## Target architecture

```text
Models/
├── AIStreamEvent.swift          # reasoning/text/tool/transport-neutral stream vocabulary
├── AIReasoningBlock.swift       # visible summary + provider-owned opaque continuation data
├── AIMessage.swift              # assistant turn may carry preserved reasoning blocks
├── ChatGPTClient.swift          # existing Chat Completions compatibility parser
└── ClaudeClient.swift           # thinking/signature/text/tool block parser

Features/AI/
├── AIWritingSession.swift       # reasoningText, answerText and phase transitions
├── AIReasoningTraceView.swift   # isolated SwiftUI presentation and disclosure behavior
├── AIWritingView.swift          # composes trace + existing answer preview
└── AIStreamingPreview.swift     # remains answer-only Markdown renderer
```

Parser types must become internal/testable rather than private implementation islands. Provider-specific wire data stays in provider files; the UI sees only neutral visible reasoning text and state. `AIMessage` may carry an opaque/provider-tagged block solely so Anthropic tool continuations can serialize the exact required transport data.

## Dependency graph

`S1 → S2 → S3 → S4 → S5`

## Phases / Steps

### S1 — 供应商契约与统一推理事件模型

- Goal: 在写请求代码前钉死“哪些 wire 事件算 reasoning、如何排序、哪些元数据必须回填”，消除调研文档时效性与兼容代理差异带来的最大风险。
- Depends on: none
- Refs: C1, C3–C10, C14 — 需求、调研、当前官方契约与现有协议边界。
- Resolves: Chat Completions reasoning 字段白名单；Claude 主动请求 thinking 的安全边界。
- Sub-steps:
  - S1.1 收集去敏后的 OpenAI-compatible Chat Completions 与 Anthropic-compatible Messages SSE fixture，覆盖 reasoning→text、tool use、无 reasoning、未知事件与结束事件。
  - S1.2 建立 wire-event mapping 表，明确 Chat Completions 只接受哪些显式 reasoning 字段，禁止解析正文里的 `<think>` 标签作为默认行为。
  - S1.3 定义请求兼容策略：设置仅展示 OpenAI/Anthropic；保留旧 raw value 兼容；Anthropic thinking 参数仅在官方契约与无损降级可证明时启用。
  - S1.4 定义 `AIStreamEvent`、`AIReasoningBlock` 与 assistant continuation 数据契约，明确 UI 可见文本和 provider opaque transport 的边界。
- Verify: 契约文档与 fixture 能表达两类协议所有目标序列；事件映射无歧义，依赖图和配置迁移策略无破坏性缺口。

### S2 — 请求层、SSE 解析与协议连续性

- Goal: 让两类协议把 reasoning、正文和工具事件按顺序产出，并在不支持 reasoning 时保持原有可用性。
- Depends on: S1
- Refs: C3–C10, C14 — fixture/官方契约、共享 SSE、客户端与配置模型。
- Sub-steps:
  - S2.1 抽出可测试 parser，扩展共享流事件设施，同时保持取消、HTTP 错误和“有内容后不重放”语义。
  - S2.2 扩展 Chat Completions parser 消费白名单 reasoning delta；未知字段和无 reasoning 响应保持旧行为。
  - S2.3 将配置收口为 OpenAI/Anthropic 两项，并把实验性的 `openAIResponses` 本地值迁回 OpenAI 类。
  - S2.4 扩展 Claude request/parser 处理 thinking/signature/text/tool 序列，并保证工具结果回填时 thinking blocks 原样、顺序正确地序列化。
- Verify: 所有 fixture 的事件序列断言通过；旧 AIConfig 可解码；现有 Chat Completions/Claude 无 reasoning fixture 字节级请求关键字段和正文输出不回归。

### S3 — 会话状态、正文隔离与多轮行为

- Goal: `AIWritingSession` 能独立管理本轮 reasoning 与最终正文，并在所有停止/错误/工具/精修路径下保持数据正确。
- Depends on: S2
- Refs: C10, C11 — 消息模型、工具模型和当前状态机。
- Sub-steps:
  - S3.1 增加 reasoning 缓冲、是否开始/结束 reasoning、是否开始 answer 等可观察状态；不改变 `finalText` 的正文含义。
  - S3.2 定义 loading→reasoning→streaming→done 及无 reasoning 直达 streaming 的转换，避免用字符串是否为空隐式猜阶段。
  - S3.3 处理 stop、cancel、retry、regenerate、refine、partial failure、reasoning-only completion 与空 completion，确保每轮重置不串流。
  - S3.4 在 clarify tool 回填中保存必须的 provider continuation block，但 reasoning 不进入正文历史、精修底稿或 `onAccept`。
- Verify: 纯逻辑测试覆盖事件顺序矩阵和所有对外动作；任何路径下 `finalText/onAccept` 都不含 reasoning，旧多轮/反问语义保持。

### S4 — 原生“推理轨迹”UI 与七语言可访问性

- Goal: 实现设计章节中的动态层级，让 reasoning 可读、答案优先、无 reasoning 不出现空壳。
- Depends on: S3
- Refs: C1, C2, C11–C13 — from-state、会话状态、现有生成 UI/预览与设计 token。
- Sub-steps:
  - S4.1 新建单一职责 `AIReasoningTraceView`，实现轨迹线、状态标题、限高滚动、流式贴底和展开/收拢。
  - S4.2 将 loading/reasoning/answer 三态接入 `AIWritingView`；第一段正文到达时自动收拢 reasoning，用户操作后不反复抢回状态。
  - S4.3 与 `AIStreamingPreview`、Jump to Latest、顶部 Stop、底部 RefineBar 和中断 banner 协作，处理 iPhone/iPad 与键盘/横屏空间。
  - S4.4 补齐 Reduce Motion、VoiceOver live-region/标签、Dynamic Type、触控目标、深浅色和高对比度；动画只服务阶段转换。
  - S4.5 新增/修改文案补齐简中、英、繁中、日、韩、德、俄，并审计无 emoji、SF Symbols 与词义一致性。
- Verify: 状态截图矩阵与真机/模拟器交互符合 wireframe；reasoning 长短、展开收拢、旋转、字号和无障碍下不遮挡正文或操作。

### S5 — Fixture 测试、性能、回归与发布收口

- Goal: 用协议 fixture、状态测试和设备矩阵证明功能不会污染文档或破坏既有 AI 写作链路。
- Depends on: S4
- Refs: C2–C14 — 全部输入、契约、实现边界和视觉基线。
- Sub-steps:
  - S5.1 完成两类协议 parser fixture 测试：碎片边界、Unicode、未知事件、重复结束、tool interleave、取消和 4xx fallback。
  - S5.2 完成 session 测试：reasoning-only、reasoning+text、text-only、stop/retry/refine/regenerate、partial failure 与 tool continuation。
  - S5.3 压测长 reasoning 与高频 delta，确认主线程、滚动跟随和 Markdown WebView 合帧无明显卡顿或内存异常。
  - S5.4 回归附件、图片/PDF、文档引用、反问、接受、放弃、精修、重新生成和两类旧配置。
  - S5.5 完成七语言 catalog 审计、Debug/Release 构建、iPhone/iPad 深浅色与辅助功能验收，并记录已知兼容代理限制。
- Verify: Definition of Done 全部满足；测试、Debug/Release 构建与设备矩阵通过；接受/保存的 Markdown 与 reasoning 完全隔离。
