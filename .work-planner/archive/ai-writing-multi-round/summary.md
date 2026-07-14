# Plan Summary

## Goal
把 AI 写作从「一次性生成、只能预览」升级为「可多轮对话式精修」：
生成完成后仍保留输入与按钮，用户可继续让 Agent 调整或重新生成；
并让模型在诉求含糊时通过 **function tool 反问**澄清需求（单选/多选/文字），
答完再继续生成。最后补齐旧计划遗留的「首页大号 AI 入口」，闭合端到端。

## Scope
- In:
  - AIClient 支持 function tool calling（OpenAI 与 Anthropic 两种格式）。
  - 定义一个「反问澄清」工具：一次一个问题，回答方式 单选/多选/文字；选择型带可选项与推荐项。
  - 工具调用内容**绝不渲染进正文区**，App 拿到后可视化成答题卡片供用户交互；答案回填后继续生成。
  - AIWritingSession 从一次性改为**多轮会话**：持有消息历史，支持反问→答→续、以及生成完成后的二次精修/重新生成。
  - 生成完成后 UI 保留输入与按钮（底部输入坞），可继续调整。
  - 反问仅对「自由创作/自定义」动作开启（续写/润色/整理不带工具）。
  - 端点不支持 tools 时优雅降级为直接生成。
  - 首页大号 AI 入口（承接旧计划未完成项）。
- Out:
  - 不做真正的多消息「聊天记录列表」UI（保持单预览 + 精修坞，不是完整聊天窗）。
  - 不引入除「反问澄清」外的其它业务工具（如联网检索、代码执行）。
  - 不改动 AIConfig 存储、主题、设置页既有结构。
  - 不支持 TextEditor 选中区域作为上下文（仍用整篇文本）。

## Constraints / Coexistence
- 复用既有基座：AIConfig/AIConfigStore、AIConfigGate 门槛、AIStreamingPreview 边收边渲染、
  AIAction 预设、Theme.aiGradient、AIAssistButton。
- 双格式由 AIConfig.responseFormat 决定，不假设 provider；BaseURL 用户自填（官方或兼容端点）。
- 本机仅 CommandLineTools 无完整 Xcode，编译/Run 验证交用户；SourceKit 跨文件报错为索引噪声。
- 最低 iOS 18；文案禁用 emoji；图标优先 SF Symbols。

## Definition of Done
- 自由创作/自定义诉求含糊时，模型能发起反问；App 渲染出单选/多选/文字答题卡片（推荐项高亮），
  答完继续生成；工具 JSON 从不出现在正文区。
- 生成完成后仍可输入新指令，让 Agent 调整或重新生成，多轮流畅、取消/中断干净。
- 首页有醒目的大号 AI 入口，一键生成整篇 → 接受新建 .md 并进入编辑。
- 端点不支持 tools 时不崩、可直接生成。
- 小屏交互友好：无长扁按钮、无贴边文案，答题卡片与精修坞留白得当。

## Key Decisions (locked)
| Decision | Choice | Why |
|---|---|---|
| 计划归属 | 独立新计划；旧 AI 写作计划归档为 archive/ai-writing-streaming-preview；旧计划唯一未完成项「首页入口」纳入本计划 S6 | 用户指定；旧计划已 89%，新功能是同族大扩展，独立跟踪更清晰 |
| 反问范围 | 反问工具仅在 custom（自由创作/首页生成整篇）动作提供 | 续写/润色/整理有明确文档上下文、诉求清晰，反问会多余打断 |
| 反问表单 | 一次一个问题卡片（tool 单次一个问题），模型可多轮追问；答题方式 单选/多选/文字，选择型带 options+推荐项 | 小屏可操作性优先，单问单卡最简洁清晰 |
| 事件模型 | AIClient.stream 产出 AIStreamEvent(text/toolCall)；tool 调用内容绝不进正文渲染区 | 文本与工具调用分流，正文区只渲染正文 |
| 多轮语义 | 会话保留 messages 历史；接受=应用最新 assistant 文本；精修=追加 user 指令再流式；反问=assistant(tool_use)+tool_result 回填 | 标准 Agent 多轮协议，双格式均可映射 |
| 降级 | 端点不支持 function tools（报错/忽略）时优雅降级为直接生成，不阻断 | 兼容端点未必支持 tools，可用性优先 |
| 交互 | 小屏优先；答题用卡片+留白，精修用底部输入坞；不要长扁按钮、不要贴边文案 | 用户明确的体验要求 |
