# Provider Fixture and Evidence Matrix（2026-08-20）

用于 S9.1 的统一清单：把“文档日期 / request / response / event fixture”集中挂到一处，作为后续 S9 全量验收的索引来源。

## 1. 文档证据基线

- 统一基线日期：`2026-08-20`（以 C2 快照 + `provider-contract-matrix-2026-08-20.md` 为冻结依据）。
- 官方文档/协议变更点以 `llm-provider-compatibility-2026-08.md`（快照）和 `provider-contract-matrix-2026-08-20.md` 的“证据规则 / 1.3 节 / 3.x 子节”作为引用入口。
- 证据条目与模型能力变更以 `ProviderRegistry` 决策与测试结论为可执行门禁。

## 2. Request fixture 清单（业务输入方向）

`AIReasoningTests/RequestContractTests.swift` 目前使用的契约片段可作为 request fixture 入口。

| Category | Coverage anchor | Scope | 主要 Provider | 说明 |
|---|---|---|---|---|
| Baseline request | `testConservativeCustomChat` | Custom OpenAI-compatible | custom | 保守 baseline：`model/messages/stream` + system date context；不发送 reasoning/search/file/image/pdf 非确认字段 |
| Profile-driven transport | `testProfileDrivenOpenAITransport` | OpenAI / Gemini | openAI, gemini | endpoint 与 header 归属检查（Authorization / Content-Type / `x-goog-api-client`） |
| Image serializer request | `testVerifiedImageSerialization` + `testOpenAIAdapterGoldenRequests` | OpenAI-side adapters | OpenAI/Gemini/xAI/Qwen/Kimi/GLM/MiniMax/Mistral/OpenAI-search family | 嵌套 `image_url.url` 与 Mistral string 方言分离；未验证 provider 不发送 image/pdf |
| Tool/Search request shape | `testWebSearchRequestShapes` + `testOpenAICompatibleReasoningContinuation` | OpenAI-side adapters | OpenAI/Qwen/Kimi/GLM/DeepSeek/MiniMax/xAI/Gemini | `web_search_options` / `enable_search` / `builtin_function.$web_search` / `web_search` type / MCP 置空与偏好门禁 |
| Reasoning continuation request | `testOpenAICompatibleReasoningContinuation` | DeepSeek/MiniMax/custom | deepSeek, miniMax, custom | reasoning 字段回放边界（`reasoning_content`, `reasoning_details`, custom 禁止专有字段） |
| Anthropic request path | `testOfficialAnthropicTransport` + `testAnthropicContinuationOrder` + `testAnthropicAttachmentGates` + `testAnthropicAttachmentGates` | Anthropic | anthropic | `/v1/messages` + `x-api-key` + `anthropic-version` + image/document block 及 reasoning/tool 顺序 |
| OpenAI adapter routing | `testMiniMaxOpenAIRouting` + `testProfileDrivenOpenAITransport` | MiniMax/官方 OpenAI-side | miniMax/openAI | `plugin_web_search` 与 Anthropic search tool 均禁止；MiniMax 仍走 OpenAI Chat |
| Configuration hardening | `testCleanBreakConfiguration` | 全域 | all | legacy 值清理、APIProtocol 两项约束、默认偏好 |

## 3. Response fixture 清单（响应形态方向）

| API family | 文件 / 入口 | 覆盖范围 | 备注 |
|---|---|---|---|
| OpenAI-compatible Chat Completions | `AIReasoningTests/Fixtures/chat-text-only.sse` | text-only / no reasoning | 终态 `endTurn`，回答不误判 think 标签 |
| OpenAI-compatible Chat Completions | `AIReasoningTests/Fixtures/chat-reasoning-tool.sse` | reasoning delta + tool call | 验证 tool 回流顺序、toolUse stopReason |
| OpenAI-compatible Chat Completions | `AIReasoningTests/Fixtures/chat-reasoning-details.sse` | structured reasoning details | 维持 `reasoningDetails` 数组结构 |
| OpenAI-compatible Chat Completions | `AIReasoningTests/Fixtures/openai-web-search-tool.sse` | built-in tool 续传前置 | GLM 风格 web_search tool call 结构校验 |
| Anthropic Messages | `AIReasoningTests/Fixtures/anthropic-text-only.sse` | text-only / no thinking/tool | 终态 `endTurn` |
| Anthropic Messages | `AIReasoningTests/Fixtures/anthropic-thinking-tool.sse` | thinking + tool_use + tool result | thinking block + redacted/thinking continuation |
| Anthropic Messages | `AIReasoningTests/Fixtures/anthropic-web-search.sse` | server web_search tool_result | 仅服务端搜索验证，非 app tool call |

## 4. Event fixture 清单（事件映射方向）

`AIReasoningTests/ParserFixtureTests.swift` 与 `AIReasoningTests/Fixtures/*.sse` 共同构成 parser 层 event contract。

| Event target | Fixture | 断言入口 | 对应中立事件 |
|---|---|---|---|
| OpenAI reasoning delta | chat-reasoning-tool.sse / chat-reasoning-details.sse | `testReasoningText` assertions in ParserFixtureTests | `reasoningDelta`, `reasoningBlock` |
| OpenAI answer | chat-text-only.sse | `ParserFixtureTests` answerText | `text` |
| OpenAI tool call | chat-reasoning-tool.sse / openai-web-search-tool.sse | `toolCalls`, `stopReasons` assertions | `toolCall` |
| Anthropic thinking block | anthropic-thinking-tool.sse | `reasoningBlocks`, `toolCalls` assertions | `reasoningBlock`, `toolCall` |
| Anthropic server tool text | anthropic-web-search.sse | `serverWebSearchUseCount` assertions | `text` + server search recognition |
| OpenAI/Anthropic stop reason | 所有 SSE fixture | `stopReasons` assertions | `stopReason` |

## 5. 直接可执行项（S9.1 完成即验收）

- 任何新增/变更 provider adapter 都先补 `RequestContractTests` 对应 anchor。
- parser 层新增 event 形态必须新增 `Fixtures/*.sse` 和 `ParserFixtureTests.swift` 断言。
- 文档日期与能力表保持“确认/条件/独立服务/不支持”一致，并由本清单行内可追溯。
