# LLM Provider Compatibility Snapshot — 2026-08

This is a planning snapshot, not a permanent claim. Revalidate contract details against official documentation and real API fixtures before implementing a Provider adapter.

## Product-selected provider set

| Provider | Product transport | OpenAI-compatible API | Anthropic-compatible API | Web search in the selected transport | File / image / PDF notes |
|---|---|---|---|---|---|
| OpenAI | OpenAI Chat Completions | Native | No | Use only verified Chat Completions search models/options; Responses is outside this product contract | Files and multimodal inputs are model/API specific |
| Anthropic | Anthropic | Not used | Native | Native server tool `web_search_20250305` | PDF/document and image support are model/request-shape specific |
| Google Gemini | OpenAI | Yes for a compatibility subset | No | Grounding exists natively; exact OpenAI-compatible mapping must be verified | Native file inputs exist; compatibility subset has limitations |
| xAI | OpenAI Chat Completions | Yes | Deprecated/not used | Search documented only outside the selected Chat Completions contract is treated as unsupported until a Chat-compatible mapping is verified | Files API and multimodal support are model/API specific |
| DeepSeek | OpenAI | Yes | Yes, but not used by this product | No confirmed server-search contract on selected OpenAI Chat path; default to unsupported until verified | No general document contract assumed |
| Qwen / DashScope | OpenAI Chat Completions | Yes | Yes, but not used by this product | `enable_search` for verified Chat Completions models; Responses-style search is outside scope | File workflows are model/service specific |
| Mistral | OpenAI | Yes for Chat Completions | No | Web search is exposed through Agents/Conversations, not ordinary compatible Chat Completions | Libraries/Document Q&A are separate workflows |
| Moonshot Kimi | OpenAI | Yes | Yes, but not used by this product | Built-in `$web_search` tool calling | Files API extracts text; multimodal behavior is model specific |
| Zhipu GLM | OpenAI | Yes | Yes, but not used by this product | Native `web_search` tool shape is documented | File URL / multimodal support is model specific |
| MiniMax | OpenAI | Yes | Yes, but not used by this product | Official search is primarily documented through MCP; OpenAI-chat behavior needs fixture confirmation | Text chat docs do not imply universal image/document input |

## Architectural implications

1. “OpenAI-compatible” reliably describes basic authentication, message, streaming, and ordinary function-call conventions; it does not create a universal server-side Web Search or file contract.
2. Every Provider on the OpenAI side stays on the OpenAI SDK-compatible Chat Completions family. Provider adapters may add only documented endpoint, header, search, tool-continuation, or attachment differences; they do not switch API families.
3. Provider identity and capability are separate from transport. Unknown custom OpenAI endpoints need conservative defaults and must not receive a guessed proprietary search tool.
4. Within the selected product contract, search support has two usable shapes: provider-specific Chat Completions fields/tools and provider built-in Chat tool calls that require continuation. Responses, Agent, MCP, and native-SDK-only search services remain outside scope.
5. “Files” must be split into inline image/PDF content, uploaded-file references, retrieval/file-search, and provider library/agent workflows.

## Official documentation catalog

- OpenAI Chat Completions API: https://platform.openai.com/docs/api-reference/chat
- Anthropic tool reference: https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-reference
- Anthropic PDF support: https://platform.claude.com/docs/en/build-with-claude/pdf-support
- Gemini OpenAI compatibility: https://ai.google.dev/gemini-api/docs/openai
- Gemini partner integration limitations: https://ai.google.dev/gemini-api/docs/partner-integration
- Gemini file input methods: https://ai.google.dev/gemini-api/docs/file-input-methods
- xAI inference API: https://docs.x.ai/developers/rest-api-reference/inference
- xAI web search: https://docs.x.ai/developers/tools/web-search
- xAI files: https://docs.x.ai/developers/files
- DeepSeek protocol pricing/details: https://api-docs.deepseek.com/quick_start/pricing-details-cny/
- DeepSeek Anthropic API guide: https://api-docs.deepseek.com/guides/anthropic_api
- Qwen web search: https://help.aliyun.com/zh/model-studio/web-search/
- Qwen API key and SDK compatibility: https://help.aliyun.com/zh/model-studio/get-api-key/
- Qwen file search: https://help.aliyun.com/zh/model-studio/file-search
- Mistral web-search tool: https://docs.mistral.ai/studio-api/agents/agent-tools/websearch
- Mistral libraries: https://docs.mistral.ai/studio-api/libraries
- Mistral OpenAI migration: https://docs.mistral.ai/resources/migration-guides
- Kimi OpenAI-compatible API overview: https://platform.kimi.ai/docs/api/overview
- Kimi Claude Code / Anthropic endpoint: https://platform.kimi.ai/docs/guide/claude-code-kimi
- Kimi web search: https://platform.kimi.ai/docs/guide/use-web-search
- Kimi files upload: https://platform.kimi.ai/docs/api/files-upload
- GLM OpenAI compatibility: https://docs.bigmodel.cn/cn/guide/develop/openai/introduction
- GLM Anthropic compatibility: https://docs.bigmodel.cn/cn/guide/develop/claude/introduction
- GLM web search: https://docs.bigmodel.cn/cn/guide/tools/web-search
- MiniMax OpenAI API: https://platform.minimax.io/docs/api-reference/text-openai-api
- MiniMax Anthropic API: https://platform.minimax.io/docs/api-reference/text-anthropic-api
- MiniMax search MCP: https://platform.minimax.io/docs/token-plan/mcp-guide
