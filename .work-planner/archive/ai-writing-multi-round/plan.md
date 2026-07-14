# Plan — 多轮二次生成 + function tool 反问挖掘诉求

## Target architecture

沿用既有分层，新增/改动集中在 Models（消息与网络层）与 Features/AI（会话与 UI）。

```
Models/
├── AIMessage.swift        # 改：结构化消息，支持 assistant tool_calls 与 tool 结果
├── AITool.swift           # 新：中立工具定义 + 反问工具 schema + AIToolCall + ClarifyRequest/AnswerSpec
├── AIClient.swift         # 改：请求带 tools；stream 产出 AIStreamEvent(text/toolCall)；双格式累积解析；降级
└── AIAction.swift         # 改：custom 动作声明「提供反问工具」；messages 起手不变

Features/AI/
├── AIWritingSession.swift # 改：持 messages 多轮；phase 增 awaitingAnswer；反问→答→续、精修/重生成
├── AIWritingView.swift    # 改：done 后保留输入；接入答题卡片与精修坞；tool 内容不入正文
├── AIClarifyCard.swift    # 新：反问答题卡片（单选/多选/文字 + 推荐项高亮）
├── AIRefineBar.swift      # 新：底部精修输入坞（生成完成后保留输入+按钮，小屏友好）
├── AIStreamingPreview.swift # 复用：正文边收边渲染（不变）
└── AIConfigGate.swift     # 复用：AI 入口门槛（不变）

Features/Browser/
└── FileBrowserView.swift  # 改：挂 HomeAIButton 首页大号 AI 入口（旧计划遗留项）
```

### 事件与消息模型（核心）

**AIStreamEvent**（stream 产出）：
- `.text(String)` —— 正文增量（进正文渲染区）
- `.toolCall(AIToolCall)` —— 一次完整工具调用（累积完成后产出，绝不进正文区）

**AIMessage**（改为结构化，中立表示，双格式各自序列化）：
- `role`: system / user / assistant / tool
- `content`: String（文本）
- `toolCalls`: [AIToolCall]（仅 assistant，模型发起的调用）
- `toolCallId`: String?（仅 tool 结果消息，对应被回答的调用 id）

**AIToolCall**：`{ id, name, arguments(原始 JSON 字符串) }`

**AITool**（中立定义）：`{ name, description, parameters(JSON Schema) }`

**反问工具 `ask_clarifying_question`** 入参 schema：
- `question`: string（必填）
- `answer_type`: enum `single_select | multi_select | text`（必填）
- `options`: array<{ `label`: string, `recommended`: bool }>（select 型必填）

解析成 App 侧 `ClarifyRequest { question, answerSpec }`，`AnswerSpec` = `.singleSelect([Option])` / `.multiSelect([Option])` / `.text`，`Option { label, recommended }`。

### 双格式 tool calling 映射（务必对齐）

**OpenAI（/chat/completions）**
- 请求：`tools: [{ type:"function", function:{ name, description, parameters } }]`。
- 流式：`choices[].delta.tool_calls[]`，按 `index` 累积 `id` / `function.name` / `function.arguments`(JSON 片段拼接)；`finish_reason == "tool_calls"` 时产出 toolCall。
- 续对话：assistant 消息带 `tool_calls`；答案作为 `{ role:"tool", tool_call_id, content }`。

**Anthropic（/messages）**
- 请求：`tools: [{ name, description, input_schema }]`。
- 流式：`content_block_start` 若 `content_block.type=="tool_use"` 拿 id+name → 后续 `content_block_delta` 的 `delta.type=="input_json_delta"` 累积 `partial_json` → `content_block_stop` 产出 toolCall；文本块仍走 `content_block_delta.delta.text`。`message_stop` 结束。
- 续对话：assistant 消息 content 为 `[{type:text,...}?, {type:tool_use, id, name, input}]`；答案作为 user 消息 `[{type:tool_result, tool_use_id, content}]`。

> 因需跨行累积工具调用，SSEStream 的「纯逐行 parse」要改为**有状态解析器**：共享 runner 仍负责 HTTP/状态码/取消/错误，解析与累积移入各 client 的 Parser（`func consume(line) -> [AIStreamEvent]`）。

### 会话状态机（AIWritingSession）

phase：`idle / loading / streaming / awaitingAnswer(ClarifyRequest) / done / error(String)`（保留 interruptedReason）。

- `messages` 持有完整会话（system + user + assistant + tool 结果）。
- 起手 `start(action, context, prompt)`：装配初始 messages，custom 动作附带 `tools=[反问工具]`，流式。
- 收到 `.text` → 累积到当前 assistant 草稿，phase→streaming。
- 收到 `.toolCall(反问)` → 停止本轮流，把 assistant(草稿+toolCall) 落入 messages，解析 ClarifyRequest，phase→awaitingAnswer。**工具内容不进正文**。
- `answer(_:)` → 追加 tool 结果消息（把用户答案序列化为文本/JSON），继续流式（同 messages+tools）。
- 本轮正常结束 → assistant 文本落入 messages，phase→done。
- `refine(prompt)`（done 后）→ 追加 user 指令消息，重新流式；`regenerate()` → 重发上一轮 user 诉求。
- `accept()` 交出最新 assistant 文本；取消/中断保留已生成（沿用现有 interruptedReason 逻辑）。

## Phases / Steps

### S1 — 模型层：结构化消息 + 工具定义
- Goal: 有能表达 tool_use / tool_result 的消息模型与中立工具定义、反问工具 schema、答案数据结构。
- Sub-steps:
  - S1.1 AIMessage 改结构化（role/content/toolCalls/toolCallId），兼容既有纯文本用法
  - S1.2 AITool + AIToolCall；AIStreamEvent 事件枚举
  - S1.3 反问工具 schema（ask_clarifying_question）+ ClarifyRequest/AnswerSpec/Option 解析（含无效/空选项兜底）
- Verify: 能构造带 tool 的消息序列；能把一段工具 arguments JSON 解析成 ClarifyRequest。

### S2 — 网络层：tool calling 双格式流式
- Goal: 请求可带 tools；流式产出 AIStreamEvent；两格式都能解析文本与工具调用；不支持 tools 时降级。
- Sub-steps:
  - S2.1 stream 签名改为 `(messages, tools) -> AsyncThrowingStream<AIStreamEvent, Error>`；SSEStream 改有状态解析器
  - S2.2 OpenAI：请求带 tools；累积 delta.tool_calls；assistant tool_calls 与 role:tool 结果序列化
  - S2.3 Anthropic：请求带 tools；累积 tool_use + input_json_delta；assistant tool_use 与 tool_result 序列化
  - S2.4 降级：端点报「不支持 tools」或忽略工具时，回退为无 tools 直接生成，不阻断（记录一次提示）
- Verify: 两格式都能拿到 text 增量并在诉求含糊时拿到 toolCall；回填 tool 结果能继续；无 tools 端点仍可生成。

### S3 — 会话状态机多轮化
- Goal: AIWritingSession 从一次性变多轮，支持反问→答→续与生成后精修/重生成。
- Sub-steps:
  - S3.1 引入 messages 历史 + phase 增 awaitingAnswer；start 按动作决定是否带反问工具（仅 custom）
  - S3.2 反问流程：收 toolCall→落 assistant→解析→awaitingAnswer；answer→落 tool 结果→继续流
  - S3.3 精修/重生成：done 后 refine(prompt)/regenerate 追加消息再流；accept 取最新文本
  - S3.4 取消/停止/中断在多轮下保持干净（沿用 interruptedReason）
- Verify: 一轮反问一轮生成可串起来；done 后可多次精修；各中断路径不残留。

### S4 — 反问答题 UI
- Goal: 工具调用可视化成答题卡片，供用户交互；工具内容不进正文区。
- Sub-steps:
  - S4.1 AIClarifyCard：问题文案 + 三种答题控件（单选/多选/文字），推荐项高亮、留白得当（小屏友好）
  - S4.2 单选：点选即可提交；多选：多选 + 确定；文字：输入 + 提交；空答校验
  - S4.3 接入 AIWritingView：awaitingAnswer 时展示卡片替代正文区，答完回 session.answer 继续
- Verify: 三种答题方式都能答并继续生成；推荐项明显；工具 JSON 从不出现在正文；手机端可操作性好。

### S5 — 精修/二次生成 UI
- Goal: 生成完成后保留输入与按钮，可继续调整或重新生成。
- Sub-steps:
  - S5.1 AIRefineBar：底部精修输入坞（输入框 + 发送/重新生成），生成中禁用、完成后可用；不用长扁按钮
  - S5.2 AIWritingView：done 后同时显示预览 + 精修坞 + 接受/关闭；精修时正文区切回流式
  - S5.3 小屏布局打磨：坞高度、键盘避让、留白与文案间距
- Verify: 生成完成后能输入新指令让 Agent 调整/重生成，多轮顺畅；小屏无贴边、无长扁按钮。

### S6 — 首页大号 AI 入口（承接旧计划遗留项）
- Goal: 首页醒目大号入口，一键生成整篇 → 接受新建文档并进入编辑。
- Sub-steps:
  - S6.1 HomeAIButton：首页大号醒目入口（彩色渐变，比工具栏按钮显著）挂 FileBrowserView 根
  - S6.2 aiConfigGate 门槛 → AIWritingView(action:.custom, context:nil, 生成整篇，带反问工具)
  - S6.3 接受 → FileStore 新建 .md 写入并导航进入编辑
- Verify: 首页大按钮→（可反问）→流式→接受生成新文档并打开；配置不全被拦截并可跳配置页。

### S7 — 异常与打磨
- Goal: 边界与体验收尾。
- Sub-steps:
  - S7.1 工具 arguments JSON 不完整/解析失败的兜底（跳过反问、直接生成或提示）
  - S7.2 空答/多选未选/文字空 的校验与提示；多轮取消中断干净
  - S7.3 降级提示文案；tool 与文本混合时正文只收文本
  - S7.4 整体一致性：答题卡片 / 精修坞 / loading / 中断条 视觉统一，小屏留白复核
- Verify: 各异常路径有反馈不崩；多轮 + 反问 + 精修整体体验顺。

## Milestones
- M1 = S1–S3：tool calling + 多轮会话逻辑打通
- M2 = S4–S5：反问答题 UI + 精修 UI（交互层）
- M3 = S6：首页入口闭合端到端
- M4 = S7：异常与打磨
