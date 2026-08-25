# Native Provider API Research Snapshot

Verified: 2026-08-24

This snapshot is a planning baseline, not a permanent capability truth. S1 must reopen the linked first-party pages and freeze exact model IDs, regions, endpoint versions, request fields, stream events, citation fields, image limits, and file limits before implementation.

## Cross-provider conclusion

The six providers all expose first-party Web Search, image input, and file/document workflows, but they do not share one tool or file lifecycle. Model names and dated tool versions move independently. The implementation must therefore keep a dated provider capability manifest and default unknown models to disabled advanced capabilities.

## OpenAI

- Native route: Responses API, `POST /v1/responses`.
- Current search mechanism: hosted tool `{"type":"web_search"}`; response events/items include `web_search_call`, and source details can be requested with `include: ["web_search_call.action.sources"]`.
- Current model catalog page recommends the GPT-5.6 family and lists Web Search/File Search support on GPT-5.6 Sol, Terra, and Luna. The exact model set must be revalidated at S1 because aliases and model families change.
- Image and file input are native Response input items; File Search is a separate hosted tool and lifecycle from direct file input.
- Sources:
  - https://developers.openai.com/api/docs/models
  - https://developers.openai.com/api/reference/cli/resources/responses/methods/create
  - https://developers.openai.com/api/docs/guides/latest-model

## Anthropic

- Native route: Messages API, `POST /v1/messages`.
- Current search mechanism: Anthropic server tool. The latest documented type is `web_search_20260318`; older active variants include `web_search_20260209` and `web_search_20250305` with different capabilities.
- Model compatibility is tool-version-specific. Dynamic filtering on the 20260209-and-later tool is documented for selected current Claude 5/4.x models; S1 must freeze the exact public model IDs and select one tool version deliberately.
- Images are message content blocks. PDFs/files use document blocks and, where applicable, the Files API; thinking/signature blocks must be preserved during continuation.
- Sources:
  - https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-search-tool
  - https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-reference
  - https://platform.claude.com/docs/en/build-with-claude/pdf-support
  - https://platform.claude.com/docs/en/about-claude/models/overview

## Gemini

- Native routes to reconcile in S1: Gemini Interactions API and native `models.generateContent`; do not use the OpenAI compatibility endpoint.
- Current search mechanism: `google_search`. The current Interactions example uses `tools: [{"type":"google_search"}]`; native GenerateContent expresses the same capability as `Tool(google_search=GoogleSearch())`.
- The 2026-08-20 support table includes Gemini 3.7 Flash, 3.6 Flash, 3.5 Flash/Flash-Lite, selected Gemini 3 previews, and Gemini 2.5/2.0 models. Older models use `google_search_retrieval`; current models use `google_search`.
- Search grounding returns structured call/result steps and citation annotations/grounding metadata. Images can be inline or uploaded. Files/PDFs use the Gemini Files API and model content parts; File Search is a distinct retrieval workflow.
- Sources:
  - https://ai.google.dev/gemini-api/docs/google-search
  - https://ai.google.dev/gemini-api/docs/image-understanding
  - https://ai.google.dev/gemini-api/docs/files
  - https://ai.google.dev/gemini-api/docs/file-search

## Qwen

- Native route: DashScope text-generation and multimodal-generation APIs. Do not use Alibaba's OpenAI-compatible Chat Completions or Responses endpoints.
- Current native search mechanism: `enable_search: true` plus `search_options` under DashScope parameters. Search options cover forced search, strategy, freshness, source return, citations, and site filters with model-specific restrictions.
- Native multimodal search uses `MultiModalConversation`/multimodal-generation, requires streaming, and uses `search_strategy: "agent"` for the documented current multimodal models.
- The current search page mentions Qwen 3.8/3.7/3.6/3.5 families for its Responses route but uses `qwen-plus` and Qwen 3.5 multimodal models in native DashScope examples. S1 must not copy the compatibility-route model list into the native adapter; it must freeze the native DashScope model matrix separately.
- Files and extraction/retrieval have their own DashScope/Model Studio workflows and must not be treated as inline image blocks.
- Sources:
  - https://help.aliyun.com/zh/model-studio/web-search/
  - https://help.aliyun.com/zh/model-studio/qwen-api-via-dashscope
  - https://help.aliyun.com/zh/model-studio/vision

## Kimi

- Native route: Moonshot/Kimi first-party chat, model, file, and Formula APIs. Similarity to OpenAI field names does not make this an OpenAI adapter.
- Current recommended model: `kimi-k2.6`; `kimi-latest` is documented as retired.
- Direct built-in search mechanism: a tool with `type: "builtin_function"` and `function.name: "$web_search"`. The current documentation requires thinking to be disabled for Kimi K2.6/K2.5 when this built-in tool is used.
- Alternative first-party search mechanism: Formula `moonshot/web-search:latest`, which returns protected encrypted output for continuation. S1 must select the product path deliberately rather than mixing both lifecycles.
- Kimi K2.6 supports text, image, and video input. Large/reused media use uploaded file IDs; general documents use the documented Files/extract workflow.
- Sources:
  - https://platform.kimi.com/docs/models
  - https://platform.kimi.com/docs/guide/kimi-k2-6-quickstart
  - https://platform.kimi.com/docs/guide/use-web-search
  - https://platform.kimi.com/docs/guide/use-official-tools
  - https://platform.kimi.com/docs/api/files

## GLM

- Native route: Zhipu/BigModel `POST /api/paas/v4/chat/completions`; the standalone `POST /api/paas/v4/web_search` is a separate first-party search API.
- Current chat search mechanism: `tools` entry with `type: "web_search"` and a provider-owned `web_search` configuration object. Current official SDK examples use `glm-5.2` and can request source results.
- Current flagship text model: `glm-5.2`. Its model page describes text input; visual/file support must therefore be gated to the exact visual or multimodal models listed by the chat API rather than inferred from the provider-level endpoint.
- Search responses expose provider-owned `web_search` source records. The app must normalize them to citations without discarding the original fields needed for debugging and display.
- Sources:
  - https://docs.bigmodel.cn/api-reference/%E6%A8%A1%E5%9E%8B-api/%E5%AF%B9%E8%AF%9D%E8%A1%A5%E5%85%A8
  - https://docs.bigmodel.cn/cn/guide/develop/python/introduction
  - https://docs.bigmodel.cn/api-reference/%E5%B7%A5%E5%85%B7-api/%E7%BD%91%E7%BB%9C%E6%90%9C%E7%B4%A2
  - https://docs.bigmodel.cn/cn/guide/models/text/glm-5.2

## Planning risks to resolve in S1

| Risk | Why it matters | Required resolution |
|---|---|---|
| "Latest model" drift | Aliases, previews, and dated model IDs can change without app releases | Date-stamped manifest plus conservative unknown-model behavior; use native model-list metadata only as discovery, not proof of search support |
| Tool version drift | Anthropic versions tools by date; Gemini has old/new search tool names; Kimi has two first-party search lifecycles | Freeze one supported mechanism per provider and keep the mechanism explicit in code |
| Text versus multimodal model split | Qwen and GLM use different model/endpoint constraints for image/file input | Capabilities resolve from provider + exact model + selected native route |
| File lifecycle mismatch | Direct file blocks, uploads, extraction, and retrieval are not interchangeable | Model separate direct input, uploaded reference, extraction, and hosted retrieval states |
| Citation mismatch | Sources arrive as annotations, grounding metadata, call results, or top-level arrays | Normalize for UI while preserving provider payload identity below the Adapter boundary |

