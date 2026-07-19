# Plan Summary — AI 输入附件（图片 + 引用文档）

## Goal
当前 AI 辅助生成只接受纯文字 prompt。用户在让 AI 生成内容时，常想补充自己的上下文素材：
**图片**（截图、示意图）与**现有文档**（库内已有 .md）供模型参考。

From → To：
- From：`AIWritingView` 的 prompt 只有一个 `TextField`；消息中立层 `AIMessage.content` 是纯 `String`；两家 client 只序列化字符串。
- To：生成类动作（续写 + 自由创作）的输入区可添加**相册图片**与**引用库内文档**两类附件；消息层支持多模态图片块；两家 client 各自正确序列化图片；含压缩、限张、视觉不支持等异常的完整处理。

## Scope
- **In**：
  - 相册选图（PhotosPicker，仅 image），自动压缩降采样 + 限张（默认 4）。
  - 引用 App 内现有 .md 文档（多选，整篇文本注入 user 消息）。
  - 附件条 UI（缩略图/文档 chip、删除、计数），接在续写 + 自由创作的 promptInput。
  - `AIMessage` 多模态扩展 + `ChatGPTClient`/`ClaudeClient` 两条图片序列化。
  - 异常处理：加载失败、压缩后超限、模型不支持视觉、降级重试仍带图。
- **Out（留 TODO 注释，后续迭代）**：
  - 拍照（相机）。
  - 引用外部文件（系统文件选择器、PDF/txt 等）。
  - 润色/整理动作的附件入口。

## Constraints / Coexistence
- 遵循 CLAUDE.md：单一职责、DRY、feature 分层、视图轻逻辑外移、版本差异收敛、**文案禁 emoji、图标用 SF Symbols**。
- **向后兼容硬约束**：无附件时，两家 client 的请求体必须与现状逐字节一致（user 消息保持 `"content": "<string>"`），不得因引入多模态而改变纯文本路径。
- 图片块只出现在 **user** 消息；system/assistant/tool 序列化不变。Claude 的 system 顶层字段装配不受影响。
- 引用文档是**文本注入**，不经图片块；不改消息模型，走 `AIAction.userContent` 的上下文拼装。
- 最低 iOS 18；PhotosPicker 原生可用。
- 需真实 API Key 才能端到端验证带图请求（同 i18n 计划，属用户凭据，不代填）。

## Definition of Done
1. 续写 + 自由创作的输入区可选相册图片与引用库内文档，UI 有缩略图/chip、可删除、有张数上限提示。
2. 无附件时，抓包确认两家 client 请求体与改造前逐字节一致（纯文本路径零回归）。
3. 带图请求：ChatGPT 走 `image_url` data URI、Claude 走 `image/base64` source，两条路径抓包验证均正确。
4. 引用文档内容以 `<reference>` 边界注入 user 消息，模型可据此参考；多选顺序稳定。
5. 图片自动压缩到 provider 安全尺寸、超过张数上限被拦、加载失败有可读提示。
6. 模型不支持视觉时，错误提示可读（指向「所选模型可能不支持图片」），非裸抛 provider 错误体。
7. 拍照与外部文件引用处均有明确 TODO 注释说明后续迭代。

## Context & References
| id | Source | Location | What it's for |
|---|---|---|---|
| C1 | 原始需求 + 澄清范围 | context/feature-requirements.md | 范围与边界的权威来源 |
| C2 | 两家图片请求体契约 + 压缩参数 + 异常来源 | context/image-block-api-contract.md | S3 图片序列化 / S1 压缩 / S6 异常的实现依据 |
| C3 | 消息中立层 | MarkdownApp/MarkdownApp/Models/AIMessage.swift | 多模态扩展的改造对象（S2） |
| C4 | OpenAI 序列化 | MarkdownApp/MarkdownApp/Models/ChatGPTClient.swift | image_url 块序列化点（S3） |
| C5 | Anthropic 序列化 | MarkdownApp/MarkdownApp/Models/ClaudeClient.swift | image/base64 块序列化点（S3） |
| C6 | 请求消息装配 | MarkdownApp/MarkdownApp/Models/AIAction.swift | userContent 注入文档引用 + 携带图片附件（S2/S4） |
| C7 | 输入 UI | MarkdownApp/MarkdownApp/Features/AI/AIWritingView.swift | 附件条挂载点、promptInput（S5） |
| C8 | 会话状态机 | MarkdownApp/MarkdownApp/Features/AI/AIWritingSession.swift | start(messages:) 入口，附件随消息带下去（S5） |
| C9 | 文档存储/模型 | MarkdownApp/MarkdownApp/Models/FileStore.swift, DocumentNode.swift | 引用文档的树/读取来源（S4） |
| C10 | 现成文档树选择器 | MarkdownApp/MarkdownApp/Features/Switcher/DocumentSwitcherSheet.swift | 引用文档选择器可复用的树形 UI（S4） |
| C11 | 两个 AI 入口 | FileBrowserView.swift:87, DocumentView.swift:105 | AIWritingView 拉起处，附件仅生成类动作可见（S5） |
| C12 | 降级重试 | MarkdownApp/MarkdownApp/Models/AIClient.swift | streamWithToolFallback，确认带图请求降级仍带图（S6） |

## Assumptions and Open Questions
| Item | Status | Why it matters | Resolution point |
|---|---|---|---|
| 引用文档可多选、整篇注入、超大给软提示 | assumed | 决定选择器交互与 prompt 体积 | S4 落地前，若用户纠正则改单选/截断 |
| 张数上限取 4、长边压到 ~1568px、统一转 JPEG | assumed | 决定压缩参数与请求体大小 | S1 实现时，可按实测调整 |
| 图片仅用于 user 消息、随「本轮首个 user 消息」发送（refine/regenerate 不重复带图） | assumed | 决定附件在多轮会话里的生命周期 | S5，避免每轮重复塞图撑爆上下文 |
| 附件条只在 idle（填 prompt）阶段可编辑，进入流式后只读 | assumed | 交互一致性 | S5 |

## Key Decisions (locked)
| Decision | Choice | Why |
|---|---|---|
| 启用范围 | 仅续写 + 自由创作 | 附件=额外生成参考；润色/整理作用于既有正文，语义不符（用户确认） |
| 图片来源 | 仅相册 PhotosPicker | 拍照留后续迭代（用户确认） |
| 文档来源 | 仅库内 .md | 外部文件引用留后续迭代（用户确认） |
| 图片策略 | 本地自动压缩降采样 + 限张 + 可读异常 | provider 有尺寸/张数限制、模型可能不支持视觉（用户确认） |
| 引用文档实现 | 纯文本注入 user 消息，不走图片块 | 文档是文本，注入即可，不必扩多模态；改动最小 |
| 向后兼容 | 无附件时请求体逐字节不变 | 纯文本路径零回归，多模态只在有图时启用 |
| 附件模型载体 | 新增中立 `AIAttachment`（image data / doc text），挂在 user 消息 | 收敛「附件是什么」到一处，两家 client 各自翻译 |
