# 六家强制 Web Search 契约复核（2026-08-25）

## 产品语义

用户开启 Web Search 后，每个新的用户回合都必须真实执行搜索并产生 Provider 可验证的搜索事件、结果或引用；不得依赖关键词判断，也不得在未搜索时静默退回模型参数知识。关闭时不得发送搜索字段或产生搜索费用。

## 第一方契约

| Provider | 强制方式 | 第一方依据 | 实施约束 |
|---|---|---|---|
| OpenAI Responses | 用 `tool_choice` 的 `allowed_tools` + `mode=required` 将允许工具收敛到 hosted `web_search` | https://platform.openai.com/docs/api-reference/responses-streaming/response/output_item | 不得用普通 `auto`；保留 `response.web_search_call.*` 作为执行证据。 |
| Anthropic Messages | `tool_choice={type:tool,name:web_search}` 强制指定 server tool | https://platform.claude.com/docs/en/agents-and-tools/tool-use/define-tools | 强制 tool choice 与 extended thinking 不兼容，Search 开启时关闭可展示 thinking；不支持 forced tool 的模型必须在联网前失败。 |
| Gemini Interactions | `tool_choice.allowed_tools.mode=any` 且仅允许 `google_search` | https://ai.google.dev/api/interactions-api-v1 | `google_search_call` / `google_search_result` steps 是执行证据。 |
| Qwen DashScope | `enable_search=true` + `search_options.forced_search=true` | https://help.aliyun.com/en/model-studio/qwen-api-via-dashscope | 仅 `enable_search` 仍由模型判断；必须同时设置 `forced_search`。 |
| Kimi | App 在 chat 前直接执行 Formula `moonshot/web-search:latest`，把受保护结果作为同回合 tool result 注入 | https://platform.kimi.com/docs/guide/use-official-tools | K2.6 仅接受 `tool_choice=auto/none`，不支持 `required`；Formula 与 thinking 冲突。 |
| GLM | App 在 chat 前直接调用 `POST /api/paas/v4/web_search`，再把结构化结果注入 chat | https://docs.bigmodel.cn/api-reference/%E5%B7%A5%E5%85%B7-api/%E7%BD%91%E7%BB%9C%E6%90%9C%E7%B4%A2 | Chat `tool_choice` 只有 `auto`；独立 Search API 使用 `search_intent=false` 才是确定性搜索。Query 最长 70 字符。 |

## 回归要求

1. Search 开启时，六家 request fixture 必须锁定上述强制字段或 preflight 请求。
2. Search 关闭时，六家不得发送搜索工具、forced flag 或 preflight 请求。
3. 模型/工具版本不支持强制搜索时，在网络请求前给出明确错误，禁止静默回答。
4. 每个开启搜索的回合必须至少出现 `search.started`，并以 Provider 搜索结果、引用或 completed event 闭环。
5. 搜索查询、结果正文、API Key 不进入 Debug 日志。
