# Native Provider Contract Freeze

Frozen: 2026-08-24

## Rules

- Only OpenAI, Anthropic, Gemini, Qwen, Kimi and GLM are production Provider identities.
- Each identity owns one first-party contract. Similar JSON shapes do not permit serializer/parser reuse.
- Advanced capability gates use exact documented model IDs from this snapshot. Unknown models retain basic configuration validity but receive no guessed search/image/file fields.
- The manifest carries a verified date; implementation work must reopen official documentation when that date is stale.
- A Base URL override changes only the host/base path for an explicitly selected Provider. It cannot detect Provider identity or select another wire contract.
- First-party REST through URLSession is the default transport. Official SDK examples are evidence, not runtime dependencies.

## Frozen matrix

| Provider | Native route | Auth | Default model | Web Search mechanism | Search model decision | Image/file decision |
|---|---|---|---|---|---|---|
| OpenAI | POST /v1/responses | Bearer | gpt-5.6-terra | hosted tool type web_search; include web_search_call.action.sources | GPT-5.6 alias, Sol, Terra, Luna | Responses image/file input; upload reference and File Search remain separate lifecycles |
| Anthropic | POST /v1/messages | x-api-key plus anthropic-version 2023-06-01 | claude-fable-5 | server tool web_search_20260318 | exact current Claude 5/4.x IDs in manifest | image/document blocks plus Files reference; thinking signatures remain opaque |
| Gemini | POST /v1beta/interactions | x-goog-api-key | gemini-3.7-flash | google_search Interactions tool | current Google Search support table only | native image/file input and Files/File Search lifecycles |
| Qwen | native DashScope text-generation; multimodal-generation by input/model | Bearer | qwen-plus | enable_search plus search_options; multimodal uses streaming and agent strategy | only models explicitly documented on native DashScope paths; compatibility Responses list excluded | multimodal endpoint for images; upload/extract/retrieval remain explicit native workflows |
| Kimi | first-party Moonshot chat/files endpoints | Bearer | kimi-k2.6 | builtin_function named $web_search | kimi-k2.6 and kimi-k2.5 | K2.6 image input plus Files/upload/extract; search disables displayable thinking because builtin search conflicts with thinking mode |
| GLM | POST /api/paas/v4/chat/completions | Bearer | glm-5.2 | chat tool type web_search with provider-owned config | exact GLM text model list | GLM-5.2 is text/search only; image/file use exact visual IDs glm-5v-turbo and glm-4.6v |

## Search execution ownership

- OpenAI, Anthropic, Gemini, Qwen and GLM search is provider/server executed. Their events must not enter a generic client tool-result loop.
- Kimi builtin search can surface a Provider-owned tool call and requires Kimi-specific continuation. It is the only mechanism allowed to use the temporary native-search continuation branch before S10.
- Search sources remain provider-owned below the Adapter. Adapters normalize title, URL, publisher, marker and provider identity for UI citations.

## File lifecycle classification

| Class | Meaning |
|---|---|
| direct input | bytes, URL or content part participates in the current model request |
| upload reference | first-party upload returns a Provider-scoped ID with expiry and cleanup rules |
| extraction | a first-party service converts a document before model input |
| hosted retrieval | Provider-owned File Search or knowledge retrieval tool |

IDs and payloads may never cross Provider boundaries. Provider-level file support is insufficient to enable all four classes.

## Official sources

- OpenAI Models and Responses: https://developers.openai.com/api/docs/models and https://developers.openai.com/api/reference/cli/resources/responses/methods/create
- Anthropic tool reference and Web Search: https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-reference and https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-search-tool
- Gemini Google Search: https://ai.google.dev/gemini-api/docs/google-search
- Qwen native DashScope Web Search: https://help.aliyun.com/zh/model-studio/web-search/ and https://help.aliyun.com/zh/model-studio/qwen-api-via-dashscope
- Kimi models and Web Search: https://platform.kimi.com/docs/models and https://platform.kimi.com/docs/guide/use-web-search
- GLM chat and Web Search: https://docs.bigmodel.cn/api-reference/%E6%A8%A1%E5%9E%8B-api/%E5%AF%B9%E8%AF%9D%E8%A1%A5%E5%85%A8 and https://docs.bigmodel.cn/cn/guide/develop/python/introduction

