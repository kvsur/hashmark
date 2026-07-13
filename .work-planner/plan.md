# Plan — AI 写作（流式生成 + 边收边渲染 + 预览应用）

## Target architecture

```
MarkdownApp/MarkdownApp/
├── Models/
│   ├── AIConfig.swift            # 已有：baseURL/model/apiKey/responseFormat
│   ├── AIConfigStore.swift       # 已有：Application Support JSON 读写
│   ├── AIMessage.swift           # 新：role + content（组装请求用）
│   ├── AIAction.swift            # 新：续写/润色/整理/自定义 → prompt 模板 + 上下文策略
│   └── AIClient.swift            # 新：流式请求协议 + ChatGPT/Claude 两实现（AsyncThrowingStream<String>）
└── Features/AI/
    ├── AIStreamingPreview.swift  # 新：WebView 边收 delta 边渲染（marked.js 节流重渲染 + 滚底）
    ├── AIWritingSession.swift    # 新：会话状态机（idle/loading/streaming/done/error）+ 取消/累积文本
    ├── AIWritingView.swift       # 新：核心 UI——prompt 半屏→全屏、状态、接受/close(二次确认)
    ├── AIActionPicker.swift      # 新：编辑器内选动作（续写/润色/整理/自定义）
    ├── AIConfigGate.swift        # 新：入口门槛——isComplete 才放行，否则提示+跳配置页（所有入口共用）
    └── HomeAIButton.swift        # 新：首页大号 AI 入口（复用 Theme.aiGradient）
```

- 复用：WebPreviewView / marked.js 本地模板；AIConfigStore；Theme.aiGradient；AIAssistButton（编辑器/预览入口）。
- WebView 流式渲染桥：给 web 模板加 JS API `window.aiSetMarkdown(text)`（全量覆盖 + marked 重渲染 + 滚到底），Swift 侧节流（~60ms）调用；避免每 token 重渲染。
- 网络：URLSession.bytes(for:) 逐行读 SSE；ChatGPT 解析 `data:` 的 choices[].delta.content，Claude 解析 content_block_delta.delta.text；`[DONE]`/message_stop 结束。

## Phases / Steps

### S1 — AI 网络层（流式双格式）
- Goal: 用 AIConfig 发起流式请求，吐出 delta 文本流。
- Sub-steps:
  - S1.1 AIMessage（role/content）+ AIAction 请求上下文的数据结构
  - S1.2 AIClient 协议：`stream(messages:) -> AsyncThrowingStream<String>`；错误类型（无配置/网络/鉴权401/限流/解析）
  - S1.3 ChatGPTClient：OpenAI 式 /chat/completions，Bearer 鉴权，SSE 解析 delta.content
  - S1.4 ClaudeClient：Anthropic /messages，x-api-key + anthropic-version，SSE 解析 content_block_delta
  - S1.5 工厂：按 AIConfig.responseFormat 选 client；取消（Task 取消即断流）
  - S1.6 AIConfig.isComplete：baseURL/model/apiKey 均非空（AI 入口前置校验用）
- Verify: 两种格式都能拿到流式 delta；无配置/401 有明确错误；isComplete 正确判定。

### S2 — 提示词/动作预设
- Goal: 把「续写/润色/整理/自定义」表达为 prompt + 上下文注入策略。
- Sub-steps:
  - S2.1 AIAction 枚举：label、systemPrompt、上下文策略（none=新建/全文/选中）
  - S2.2 组装 messages：system + 注入文档上下文 + 用户 prompt（自定义时用户自由输入）
  - S2.3 空 prompt / 无上下文的兜底与校验
- Verify: 各动作生成的 messages 合理；自定义可自由 prompt；新建无上下文成立。

### S3 — 流式渲染（WebView 边收边渲染）
- Goal: delta 实时进 WebView 渲染，性能可控。
- Sub-steps:
  - S3.1 web 模板加 `aiSetMarkdown(text)`：marked 重渲染 + 自动滚到底
  - S3.2 AIStreamingPreview：SwiftUI 包装，接受累积文本，节流（~60ms）evaluateJavaScript
  - S3.3 性能：合帧/节流、超长文本时的表现；流结束后再定格一次
- Verify: 流式内容边出边渲染、能滚动跟随；长文本不卡死。

### S4 — AI 会话 UI（核心交互）
- Goal: 完整的一次 AI 写作交互闭环。
- Sub-steps:
  - S4.1 AIWritingSession：状态机 idle/loading/streaming/done/error + 累积文本 + cancel
  - S4.2 AIWritingView：prompt 半屏 modal（medium detent）→ 收到首个 delta 立即转全屏
  - S4.3 各状态 UI：loading 转圈、streaming 预览、error（信息+重试）、done（接受/close）
  - S4.4 接受 = 回调应用；close = 有内容则二次确认再丢弃；流中可取消
  - S4.5 共享入口门槛 AIConfigGate：AIConfig.isComplete 才进入 AI；否则 alert 提示 + 跳转 AI 配置页（AIConfigEditorView）。首页/编辑器所有 AI 入口统一走此门槛
- Verify: 半屏→全屏切换顺；loading/error/取消都稳；close 二次确认；接受回调触发；配置不全被拦截并可一键去配置。

### S5 — 首页「一键开启 AI 写作」（端到端打通）
- Goal: 首页大号入口跑通「prompt→生成整篇→接受新建文档」。
- Sub-steps:
  - S5.1 HomeAIButton：首页**大号**醒目入口（彩色渐变，比普通工具栏按钮显著）
  - S5.2 接入 AIWritingView（无上下文、用户自由 prompt）
  - S5.3 接受 → FileStore 新建 .md 写入生成内容 → 进入编辑；进入前过 AIConfigGate（配置不全先提示再跳配置页）
- Verify: 首页大按钮→半屏 prompt→全屏流式→接受生成新文档并打开；配置不全被拦截、提示并可跳配置页。

### S6 — 编辑器/预览内 AI（应用到当前文档）
- Goal: 在文档内用 AI 动作并把结果应用回文档。
- Sub-steps:
  - S6.1 AIAssistButton → AIActionPicker（续写/润色/整理/自定义）
  - S6.2 走 AIWritingView（注入当前文档/选中作上下文）
  - S6.3 接受 → 按动作应用（续写=插入文末/光标；润色/整理=替换全文），落盘
- Verify: 各动作流式生成、预览确认后正确应用到当前文档并保存。

### S7 — 异常与打磨
- Goal: 边界与体验收尾。
- Sub-steps:
  - S7.1 无配置引导（去设置页 AI 配置）串起来
  - S7.2 错误分类文案 + 重试；取消中断干净
  - S7.3 空 prompt/超长文档/断网 等边界
  - S7.4 二次确认、loading 骨架、整体一致性打磨
- Verify: 各异常路径有反馈不崩；体验顺。

## Milestones
- M1 = S1–S5：streaming 端到端跑通（首页一键生成整篇）
- M2 = S6：编辑器内 AI 动作应用到文档
- M3 = S7：异常与打磨
