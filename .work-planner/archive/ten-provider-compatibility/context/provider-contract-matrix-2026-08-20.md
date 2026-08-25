# AI Provider 契约矩阵与 S1 决策冻结（2026-08-20）

本文是 S1.2–S1.4 的冻结产物。它复核 C2 的官方资料、对照 C12 的现有实现，并规定 S2–S10 可以依赖的线协议与产品行为。除 S10 的真实凭据 smoke test 外，后续实现不得自行扩大能力。

## 1. 证据规则

- `确认`：官方文档给出当前 endpoint、字段或完整示例，可进入 adapter 与 fixture。
- `条件`：官方支持，但受模型、区域、账号、文件来源或组合能力限制；只有 Registry 的已验证规则命中时发送。
- `独立服务`：能力存在于 Responses、Agents、MCP、Files、Formula、原生 SDK 等另一流程；不能冒充本计划的 Chat Completions 能力。
- `不支持`：所选协议路径没有官方映射；UI 显示不可用，请求不发送。
- `待实测`：线格式已有官方证据，但必须在 S10 用可用凭据确认模型、区域或计费开关。待实测不等于可猜测。

安全默认：任一层状态为未知时均按“不发送”处理。官方文档没有给出的字段、内容块、工具名或续传方式不得通过 host/model 字符串猜测。

## 2. 顶层协议与路由

| Provider | 产品协议 | 官方 Base URL / 完整 endpoint | 鉴权 | 状态 |
|---|---|---|---|---|
| OpenAI | OpenAI Chat Completions | `https://api.openai.com/v1` → `/chat/completions` | `Authorization: Bearer` | 确认 |
| Anthropic | Anthropic Messages | `https://api.anthropic.com` → `/v1/messages` | `x-api-key` + `anthropic-version: 2023-06-01` | 确认；只允许官方域名 |
| Gemini | OpenAI Chat Completions | `https://generativelanguage.googleapis.com/v1beta/openai` → `/chat/completions` | `Authorization: Bearer`；发送可识别的 `x-goog-api-client` 产品/版本头 | 确认 |
| xAI | OpenAI Chat Completions | `https://api.x.ai/v1` → `/chat/completions` | `Authorization: Bearer` | 确认 |
| DeepSeek | OpenAI Chat Completions | `https://api.deepseek.com` → `/chat/completions`（官方也接受 `/v1` 兼容前缀） | `Authorization: Bearer` | 确认 |
| Qwen | OpenAI Chat Completions | 中国区 `https://dashscope.aliyuncs.com/compatible-mode/v1`；国际区 `https://dashscope-intl.aliyuncs.com/compatible-mode/v1` → `/chat/completions` | `Authorization: Bearer` | 确认；区域由用户 endpoint 决定 |
| Mistral | OpenAI Chat Completions | `https://api.mistral.ai/v1` → `/chat/completions` | `Authorization: Bearer` | 确认 |
| Kimi | OpenAI Chat Completions | 国际 `https://api.moonshot.ai/v1`；中国区 `https://api.moonshot.cn/v1` → `/chat/completions` | `Authorization: Bearer` | 确认；区域由用户 endpoint 决定 |
| GLM | OpenAI Chat Completions | `https://open.bigmodel.cn/api/paas/v4` → `/chat/completions` | `Authorization: Bearer` | 确认；Coding 套餐专属 endpoint 不作为普通默认值 |
| MiniMax | OpenAI Chat Completions | 国际 `https://api.minimax.io/v1`；中国区 `https://api.minimaxi.com/v1` → `/chat/completions` | `Authorization: Bearer` | 确认；旧 `/v1/text/chatcompletion_v2` 已废弃，不接入 |
| Custom | OpenAI Chat Completions | 用户 Base URL 规范化后补 `/chat/completions` | 默认 `Authorization: Bearer` | 尽力兼容；只启用保守基线 |

所有 OpenAI-side Provider 只使用 Chat Completions。即使某家官方更推荐 Responses、Anthropic-compatible、Agents、MCP 或原生 SDK，本产品也不切换 API 家族。

## 3. 能力矩阵

缩写：`F` 普通 function calling；`S` 流式；`R` reasoning 解析/续传；`W` Web Search；`I` 图片；`P/F` PDF 或文件。`✓` 为确认，`△` 为条件，`—` 为不支持，`独立` 为所选 Chat 路径之外。

| Provider | S | F | R | W（Chat 路径） | I | P/F | 关键限制 |
|---|---:|---:|---:|---|---|---|---|
| OpenAI | ✓ | △ | △ | △ `web_search_options` | △ `image_url` | — | Search Preview 模型不支持 function calling 或图片；搜索仅限官方明确支持的模型，当前已出现弃用状态 |
| Anthropic | ✓ | ✓ | △ thinking block | ✓ `web_search_20250305` | △ image block | △ document block | 搜索由服务端在同一 Messages 请求内执行；组织可禁用；图片/PDF 受模型和大小限制 |
| Gemini | ✓ | △ | △ | — | △ OpenAI `image_url` | — | Grounding with Google Search 与 File API 属于原生/高级集成，不映射到所选兼容路径 |
| xAI | ✓ | △ | △ | — | △ OpenAI `image_url` | 独立 | Web Search 与 Files 的官方集成落在 Responses/xAI SDK 路径 |
| DeepSeek | ✓ | ✓ | △ `reasoning_content` | — | — | — | 工具续传时必须保留官方要求的 reasoning 数据；Chat schema 仅确认文本和 function tool |
| Qwen | ✓ | △ | △ | △ 顶层 `enable_search: true` | △ OpenAI `image_url` | 独立 | 搜索、视觉、工具+流均需模型级规则；原生多模态/文件流程不能泛化 |
| Mistral | ✓ | ✓ | △ | — | △ 字符串型 `image_url` | △ `document_url` | Web Search 只在 Conversations/Agents；图片方言与 OpenAI 嵌套对象不同；本地 PDF base64 未冻结 |
| Kimi | ✓ | ✓ | △ `reasoning_content` | △ `builtin_function.$web_search` | △ OpenAI `image_url` | 独立 | 搜索需要客户端工具回传循环；多模态限模型；文档解析通过 Files `file-extract` 流程 |
| GLM | ✓ | ✓ | △ `reasoning_content` | △ `type:web_search` | △ OpenAI `image_url` | △ `file_url` | 搜索需 `enable:true`；图片/文件限视觉模型；已确认 PDF 仅以可访问 URL 示例 |
| MiniMax | ✓ | ✓ | △ `reasoning_details` / `<think>` | — | △ OpenAI `image_url` | — | 当前多模态 Chat 仅 MiniMax-M3；完整 assistant/reasoning 必须回放；搜索仅有 MCP 等独立工具 |
| Custom | △ | △ | — | — | — | — | 只发送标准文本、stream 和普通 function 基线；服务端拒绝时给出尽力兼容错误，不升级方言 |

### 3.1 OpenAI

- Search 只允许 Registry 中官方明确支持 Chat Completions 搜索的精确模型 ID，序列化 `web_search_options`。不按 `gpt-*` 模糊匹配。
- Search Preview 模型与 app 的普通 function tools、图片互斥；有效能力解析必须在发请求前阻止组合。
- 图片只对已验证视觉模型使用 OpenAI `image_url.url`。PDF/file 的 Chat 内容块未在本轮得到足以冻结的精确证据，因此先不发送；S7 可在新增官方证据与 fixture 后升级。
- 记录响应 `x-request-id`；可发送不含隐私的 `X-Client-Request-Id` 作为关联 ID。

证据：[API authentication and request IDs](https://developers.openai.com/api/reference/overview)、[GPT-4o Search Preview](https://developers.openai.com/api/docs/models/gpt-4o-search-preview)、[GPT-4o mini Search Preview](https://developers.openai.com/api/docs/models/gpt-4o-mini-search-preview)、[GPT-5 model capabilities](https://developers.openai.com/api/docs/models/gpt-5)。

### 3.2 Anthropic

- 固定 `/v1/messages`、`x-api-key` 与 `anthropic-version`；不接受第三方 Base URL。
- Web Search 序列化为 `tools: [{"type":"web_search_20250305","name":"web_search",...}]`。这是服务端工具，不生成由 app 执行的 tool result 循环。
- 图片使用 `image` content block；PDF 使用 `document` content block。只对官方文档确认的 source 类型、模型、大小/页数约束开放。
- thinking、tool_use、server_tool_use、web_search_tool_result 与正文分别解析，未知 block 映射为可诊断错误。

证据：[Messages API](https://platform.claude.com/docs/en/api/messages/create)、[Authentication](https://platform.claude.com/docs/en/manage-claude/authentication)、[Web search tool](https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-search-tool)、[Vision](https://platform.claude.com/docs/en/build-with-claude/vision)、[PDF support](https://platform.claude.com/docs/en/build-with-claude/pdf-support)。

### 3.3 Gemini

- 使用 Google 的 OpenAI compatibility Base URL，并附加能标识本 app/版本的 `x-goog-api-client`；值不得含用户内容。
- 标准 function calling、stream 与 `image_url` 均按模型条件开放。
- Google Search Grounding 与 Gemini File API 在官方文档中要求原生/手动高级集成，本计划的 Chat compatibility adapter 不发送。

证据：[OpenAI compatibility](https://ai.google.dev/gemini-api/docs/openai)、[Partner integration requirements](https://ai.google.dev/gemini-api/docs/partner-integration)。

### 3.4 xAI

- 使用标准 Chat Completions stream 与 function tools，实际能力受模型页约束。
- Web Search 官方示例落在 xAI SDK 或 OpenAI Responses，不在本计划路径；文件引用同理。
- 图片只对模型 Registry 明确为视觉输入的模型发送 OpenAI `image_url`。

证据：[REST inference compatibility](https://docs.x.ai/developers/rest-api-reference/inference)、[Chat Completions](https://docs.x.ai/developers/rest-api-reference/inference/chat)、[Streaming](https://docs.x.ai/developers/model-capabilities/text/streaming)、[Web Search](https://docs.x.ai/developers/tools/web-search)、[Files](https://docs.x.ai/developers/files)。

### 3.5 DeepSeek

- 使用标准 Chat Completions、SSE 与 `function` tools；不注入搜索工具或媒体内容块。
- 解析 `reasoning_content`。思考模型在 tool continuation 中要求回放 assistant 的 reasoning 数据；中立历史模型必须能保存这一 provider opaque continuation 数据，不能只保留正文/tool_calls。

证据：[Create Chat Completion](https://api-docs.deepseek.com/api/create-chat-completion)、[Tool calls](https://api-docs.deepseek.com/guides/tool_calls)、[Thinking mode](https://api-docs.deepseek.com/guides/thinking_mode)。

### 3.6 Qwen

- Web Search 的 Chat 方言是顶层 `enable_search: true`，仅对官方列出的兼容模型开放；不再把这一字段泛化到其他 Provider。
- function、stream、视觉输入以及它们的组合必须按精确模型能力决策。视觉模型的 `image_url` 使用 OpenAI-compatible 形式。
- 文档/文件能力若需 DashScope 原生 endpoint，归为独立服务；本轮 Chat adapter 不发送。

证据：[OpenAI compatibility](https://help.aliyun.com/zh/model-studio/compatibility-of-openai-with-dashscope)、[Web Search](https://help.aliyun.com/zh/model-studio/web-search)、[Streaming](https://help.aliyun.com/zh/model-studio/stream)、[Function calling](https://help.aliyun.com/zh/model-studio/qwen-function-calling)。

### 3.7 Mistral

- Web Search 仅属于 Conversations/Agents，不向 `/v1/chat/completions` 发送 `web_search`。
- 图片是 Mistral 特有的 `{"type":"image_url","image_url":"<URL-or-data-URI>"}` 字符串形态，不使用 OpenAI 的嵌套 `{url: ...}`。
- Document QnA 的 Chat content block 是 `document_url`。本轮只确认了可访问 URL；本地 PDF 的 base64 形态在取得精确 fixture 前不可发送，可继续使用 app 侧文本提取降级。

证据：[Chat API](https://docs.mistral.ai/api)、[Agent web search](https://docs.mistral.ai/studio-api/agents/agent-tools/websearch)、[Vision](https://docs.mistral.ai/studio-api/conversations/vision)、[Document QnA](https://docs.mistral.ai/studio-api/document-processing/document_qna)、[Function calling](https://docs.mistral.ai/studio-api/conversations/function-calling)。

### 3.8 Kimi

- 标准 endpoint、Bearer、stream 与普通 function tool 均确认。
- `$web_search` 声明为 `{"type":"builtin_function","function":{"name":"$web_search"}}`。模型返回 tool call 后，app 必须完整追加 assistant message，并以相同 `tool_call_id`/`name` 的 `role:tool` 消息原样回传 arguments，循环到 `finish_reason=stop`；设置有界循环和重复检测。
- 图片使用 OpenAI `image_url.url`，仅对 Kimi 视觉模型；URL 图片目前不支持时使用 data URI 或 `ms://file_id`。PDF/文档通过 Files `file-extract` 后把提取文本加入 messages，不伪装成直接 PDF Chat block。
- thinking/reasoning 与工具续传必须保留 provider opaque 字段；模型级参数限制由 Registry 管理。

证据：[API overview](https://platform.kimi.ai/docs/api/overview)、[Chat Completions](https://platform.kimi.ai/docs/api/chat)、[Web Search](https://platform.kimi.ai/docs/guide/use-web-search)、[Upload File](https://platform.kimi.ai/docs/api/files-upload)。

### 3.9 GLM

- Web Search 使用 `tools: [{"type":"web_search","web_search":{"enable":true,...}}]`；`enable` 缺省为 false。可选字段只有在 UI/Registry 有明确产品值时发送，不能硬编码过期 search prompt。
- stream 为 SSE，并以 `[DONE]` 结束；`tool_stream`、thinking/reasoning 受模型限制。
- 图片使用嵌套 `image_url.url`。GLM-4.6V 官方确认 `file_url.url` 可引用 PDF/文本公网 URL；本地 base64 PDF 未确认，默认走文本提取降级。

证据：[Chat Completions](https://docs.bigmodel.cn/api-reference/%E6%A8%A1%E5%9E%8B-api/%E5%AF%B9%E8%AF%9D%E8%A1%A5%E5%85%A8)、[Web Search](https://docs.bigmodel.cn/cn/guide/tools/web-search)、[OpenAI compatibility](https://docs.bigmodel.cn/cn/guide/develop/openai/introduction)、[GLM-4.6V files](https://docs.bigmodel.cn/cn/guide/models/vlm/glm-4.6v)。

### 3.10 MiniMax

- 当前 OpenAI-compatible endpoint 是标准 `/v1/chat/completions`；废弃的 `/v1/text/chatcompletion_v2` 不得出现在 Registry 或 fallback。
- 普通 `tools` 已确认。多轮 Function Call 必须把完整 assistant message 回放；启用 `reasoning_split: true` 后解析并保存 `reasoning_content` / `reasoning_details`，否则旧模型的 `<think>` 内容也必须保真。
- 仅 MiniMax-M3 的当前 OpenAI Chat 文档确认图片/视频内容块；图片使用嵌套 `image_url.url`。PDF 不支持。
- 网络搜索在当前官方资料中属于 MCP/外部工具，不是 `/chat/completions` 内置搜索；不再发送 `plugin_web_search`，也不走 Anthropic 代理。

证据：[International OpenAI compatibility](https://platform.minimax.io/docs/api-reference/text-openai-api)、[China-region model invocation](https://platform.minimaxi.com/docs/guides/text-generation)、[MCP search and image tools](https://platform.minimaxi.com/docs/token-plan/mcp-guide)、[Deprecated ChatCompletion v2](https://platform.minimax.io/docs/api-reference/text-post)。

## 4. Adapter 冻结表

| Adapter | 基线外允许写入的请求差异 | 必须解析/续传 | 禁止行为 |
|---|---|---|---|
| OpenAI | `web_search_options`（精确 search model）、`image_url`（精确 vision model）、可选关联 ID header | 标准 delta/tool calls；request id | 把 search model 与 function/image 混用；发送未验证 file block |
| Gemini | `x-goog-api-client`、条件 `image_url` | 标准兼容流/tool | 发送 native grounding/File API 字段 |
| xAI | 条件 `image_url` | 标准兼容流/tool/reasoning | 为 Search/Files 切 Responses |
| DeepSeek | 无搜索/附件扩展 | `reasoning_content` 与完整 tool continuation | 丢弃思考续传；伪造搜索工具 |
| Qwen | 条件 `enable_search:true`、条件 `image_url` | 标准 tool；模型特定 reasoning | 对未知模型开启 search/vision |
| Mistral | 字符串型 `image_url`；条件 URL 型 `document_url` | 标准 tool/reasoning | 在 Chat 发送 Agent `web_search`；把图片写成嵌套对象 |
| Kimi | `builtin_function.$web_search`、条件 `image_url`、模型参数 | 完整 assistant + 原样 tool result 的有界搜索循环；reasoning | 将 `$web_search` 当服务端一次完成；把 Files 流程伪装成 PDF block |
| GLM | `type:web_search` + `enable:true`；条件 `image_url`/`file_url`；模型参数 | reasoning、tool/search 元数据 | 沿用 Kimi/Anthropic 搜索语法；向非视觉模型发附件 |
| MiniMax | `reasoning_split:true`；M3 条件 `image_url` | 完整 assistant、`reasoning_details`/`reasoning_content`/必要时 `<think>` | 使用已废弃 endpoint；发送 `plugin_web_search`；走第三方 Anthropic |
| Custom | 无 | 标准 text/SSE/function best effort | 任何 Provider 专有搜索、reasoning 或附件方言 |

共享 serializer 只拥有 `model`、文本 messages、`stream`、标准 function tools/tool results 和明确的通用采样字段。所有表中差异只能由已解析的 Provider Adapter 注入。

## 5. S1.4 UX 决策

### 5.1 Provider 识别与覆盖

1. `API Protocol` 是设置页第一项，只有 OpenAI 与 Anthropic。
2. OpenAI 协议下 Provider 默认 `自动`：官方域名确定性识别；未知域名解析为 `Custom OpenAI-compatible`。
3. 未知/网关域名允许高级手动选择九家 OpenAI-side Provider，以便网关透传专有字段。界面必须提示“请确认网关支持该提供商扩展”。
4. 官方域名与手选 Provider 冲突时不允许保存；不能用手选覆盖把 `api.x.ai` 伪装为 Kimi。
5. Anthropic 协议下 Provider 固定为 Anthropic；Base URL 隐藏或只读为 `https://api.anthropic.com`，运行时再次校验 host，不提供自定义 Anthropic endpoint。

### 5.2 偏好与有效能力

- `Web Search` 是用户偏好，默认开启并跨 Provider 切换保留。实际能力为 `preference && provider adapter && model rule && endpoint rule`；不满足时 UI 显示不可用原因，请求不发送，但不篡改保存的偏好。
- 图片/PDF/文件是否可选由有效能力派生，不提供“我认为模型支持”的手工 capability 开关。能力未知时禁用选择，并说明需使用已验证模型或文本提取降级。
- Provider capability 是上限，不代表所有模型都支持。模型规则只使用官方文档中的精确 ID/系列和明确版本边界；禁止宽泛 substring 猜测。
- 组合限制（例如 OpenAI Search Preview 不能与 function/image 共用）属于有效能力决策，必须在 UI 与请求前校验两次。
- 正式支持的十家 Provider 始终可见；Custom 始终标为尽力兼容。

### 5.3 执行期验证边界

- S2–S9 只能实现本文 `确认` 或有明确门控的 `条件` 项，并用 request/response fixture 证明没有额外字段。
- S10 逐家记录真实凭据可用性、区域、模型、组织开关和计费前置条件；实测与文档冲突时降低能力，不放宽猜测。
- OpenAI Search Preview 的实际可用模型、Mistral 本地 PDF base64、GLM 本地 PDF、网关专有字段透传等，未有精确证据前保持关闭。

## 6. S1 验证结论

- 十家正式 Provider 与 Custom 均有明确协议、endpoint、auth、stream/tool/search/附件状态。
- 所有高风险旧行为都有替代决策：URL 不再切协议、未知 endpoint 不再获得 GLM 搜索、附件不再全 Provider 通发、第三方 Anthropic/MiniMax `plugin_web_search` 被删除。
- 所有未完全确认项都被标为条件、独立服务、不支持或待 S10 实测，并绑定“不发送”的安全默认；没有未标注的 wire-shape 假设。
- S1.2、S1.3、S1.4 的验收条件满足，S2 可据此开始。
