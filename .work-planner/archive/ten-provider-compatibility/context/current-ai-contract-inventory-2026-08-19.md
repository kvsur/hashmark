# Current AI Contract Inventory — 2026-08-19

S1.1 audit of the implementation and executable fixtures before the Provider redesign. This is an as-is inventory, not a statement that the current wire shapes are correct for every Provider.

## Classification

- **Reuse**: behavior or abstraction that can survive the redesign with focused adaptation.
- **Refactor**: useful behavior whose ownership or type boundary must change.
- **Contradiction**: current behavior conflicts with the locked product direction or conservative capability rules.
- **Remove**: legacy or out-of-scope behavior that the clean break explicitly deletes.
- **Gap**: required behavior or evidence does not exist yet.

## Configuration and protocol routing

| Area | Current behavior | Classification | Required follow-up |
|---|---|---|---|
| Protocol model | `AIConfig.ResponseFormat` exposes `.chatGPT` and `.claude`, labels them OpenAI and Anthropic, and defaults to `.chatGPT`. | Refactor | Replace with `APIProtocol.openAI/.anthropic`; preserve the two-label product surface, not the legacy names. |
| Persistence | Custom decoding accepts missing capability flags and migrates `openAIResponses` to `chatGPT`. | Remove / Contradiction | The app is unreleased and the plan requires a clean break; remove migration and legacy raw values. |
| Protocol inference | `suggestedResponseFormat` switches to Anthropic when `baseURL` contains `anthropic`; the settings view applies it on blur and save unless manually overridden. | Contradiction | Protocol must be the first explicit choice; URL must identify a Provider/profile, not silently change protocol. |
| Provider identity | No Provider type or registry exists. Runtime routing knows only protocol and scattered host checks. | Gap | Add `AIProvider`, adapter/profile and centralized registry. |
| Factory | `AIClientFactory` selects `ChatGPTClient` or `ClaudeClient` only from `responseFormat`. It cannot reject invalid Provider/protocol combinations. | Refactor | Resolve a validated Provider profile first; only official Anthropic may create the Anthropic client. |
| Capability preferences | `supportsImages` and `supportsWebSearch` are user booleans stored directly on the config. | Refactor | Treat them as preferences, separate from effective Provider/model/adapter capabilities. |
| Completeness | `isComplete` trims and checks Base URL, model and key only. It does not validate scheme, Provider, official Anthropic host or protocol compatibility. | Gap | Introduce pure configuration validation and user-facing reasons. |

## Settings UI

| Area | Current behavior | Classification | Required follow-up |
|---|---|---|---|
| Layout | Endpoint/model and authentication appear before the protocol picker. | Contradiction | Put OpenAI/Anthropic protocol selection first. |
| Provider guidance | No supported-Provider list, Provider selection, detected Provider, best-effort custom label or capability explanation exists. | Gap | Explicitly show all ten supported Providers and distinguish custom OpenAI-compatible endpoints. |
| Anthropic endpoint | The user can enter any Base URL and the footer explicitly promises custom roots/full endpoints work. | Contradiction | Lock or validate Anthropic to the official service. |
| Attachments | One toggle combines image and PDF support and delegates truth entirely to the user. | Refactor | Split image/PDF/file capabilities and show effective availability. |
| Search | One toggle claims the endpoint's server-side tool will be used; no Provider/model availability is shown. | Contradiction | Keep the preference default on, but gate the request and explain unsupported/conditional states. |
| Localization | All visible strings currently flow through SwiftUI localization keys, but the redesign has no new seven-language keys or UI-state tests yet. | Reuse / Gap | Preserve localization routing and add translations, accessibility and state coverage in S3. |

## Shared client and endpoint behavior

| Area | Current behavior | Classification | Required follow-up |
|---|---|---|---|
| Neutral client contract | `AIClient.stream(messages:tools:)` exposes a protocol-neutral async event stream. | Reuse | Keep the narrow interface; feed it a resolved profile/capabilities rather than raw config guesses. |
| Dynamic date/time | `SystemPromptContext` prepends exactly one `yyyy-MM-dd HH:mm:ss` system message each physical request without mutating history. | Reuse | Retain and expand regression coverage across Provider adapters and continuations. |
| Endpoint builder | `aiEndpointURL` accepts host root, `/v1`, or a full suffix and otherwise appends `/v1/<endpoint>`. | Refactor | Move default endpoints and path rules into Provider profiles; custom OpenAI may retain a conservative normalized builder. |
| Tool fallback | On an initial 4xx before any emitted event, requests containing app tools retry once with the app tools removed. Provider search injection may remain on that retry because it is driven separately by config. | Refactor / Risk | Make fallback capability-aware and observable; do not imply the retry removed all tools. |
| SSE framing | `SSEStream` reads `data:` lines and terminates when a parser reports done. | Reuse | Keep as the common transport base, adding typed terminal semantics and correlation IDs. |
| HTTP errors | Non-2xx response bodies are accumulated and may be shown truncated to the user. | Refactor / Risk | Normalize Provider errors and audit response bodies for sensitive content before diagnostics or UI exposure. |
| Diagnostics | Debug logs cover request structure, response status, parser structure, tool fallback/calls and terminal stream completion without logging prompt/text/attachments/raw arguments. | Reuse / Gap | Add Provider, correlation ID, capability decisions and explicit terminal reasons; retain privacy constraints. |

## OpenAI-compatible Chat Completions path

| Area | Current behavior | Classification | Required follow-up |
|---|---|---|---|
| Baseline request | POST to derived `/v1/chat/completions`, Bearer auth, JSON body with model/messages/stream, optional function tools. | Reuse | Make this the sole OpenAI-side API family and move endpoint/auth differences into profiles. |
| Message continuation | Assistant `tool_calls` and `role: tool` with `tool_call_id` are serialized in the conventional Chat Completions shape; optional tool name is included. | Reuse / Verify | Preserve but verify per Provider, especially built-in tool continuation. |
| Reasoning input | The client never silently enables a reasoning mode. | Reuse | Provider/model controls may be added only when documented. |
| Search: OpenAI | Exact host `api.openai.com` receives top-level `web_search_options: {}`. | Refactor / Verify | Revalidate that this is supported within the selected Chat Completions contract and model set. |
| Search: Kimi | `moonshot.ai` and `moonshot.cn` receive a `builtin_function` named `$web_search`; session echoes arguments in a tool result. | Refactor / Verify | Preserve only after official contract/fixture confirmation and type the continuation mechanism. |
| Search: DeepSeek | `deepseek.com` receives no search field/tool. | Reuse / Verify | Keep conservative absence unless official Chat documentation proves a shape. |
| Search: all other hosts | Gemini, xAI, Qwen, Mistral, GLM, MiniMax and every unknown custom host all receive the GLM-style `{type:web_search, web_search:{enable:true}}`. | Contradiction | Unknown and unsupported Providers must receive no guessed syntax; verified Providers need individual adapters (for example Qwen is expected to differ). |
| Attachments | Every Provider receives OpenAI `image_url` data URIs and `file`/`file_data` PDF blocks whenever attachments reach the client. | Contradiction | Gate each media type by verified Provider/model capability and exact request shape; never assume universal PDF support. |
| Stream parsing | Reads `choices[0].delta.content`, `reasoning_content`, `reasoning`, and fragmented `tool_calls`; flushes calls on `finish_reason=tool_calls` or `[DONE]`. | Reuse / Refactor | Keep neutral events, add Provider-specific aliases only with fixtures, and model malformed/empty/unknown terminal states. |
| Unknown/malformed chunks | Undecodable payloads, empty choices and unknown delta fields are logged/ignored; a stream can finish with no actionable event. | Refactor / Risk | Distinguish legitimate usage/control chunks from malformed or unsupported content and return a typed terminal reason. |

## Anthropic Messages path

| Area | Current behavior | Classification | Required follow-up |
|---|---|---|---|
| Endpoint and auth | POST to any derived `/v1/messages` URL with `x-api-key` and `anthropic-version: 2023-06-01`. | Contradiction / Refactor | Restrict the protocol to the official Anthropic endpoint and centralize its fixed contract. |
| Baseline body | Top-level system, model, max_tokens=4096, messages, stream=true and optional tools. | Reuse / Verify | Preserve after official revalidation; make version/max-token policy explicit. |
| Search declaration | When the preference is on, every Anthropic-format endpoint receives `web_search_20250305`, name `web_search`, max_uses=5. | Contradiction | Apply only to official Anthropic and only when current model/account capability is valid. |
| Thinking continuation | `thinking`/`redacted_thinking` blocks retain signature/encrypted data and are replayed before text and `tool_use`. | Reuse | Preserve as Anthropic-only opaque continuation data. |
| Tool continuation | `tool_use` input is reconstructed as an object; tool results become user `tool_result` blocks. Invalid JSON silently becomes `{}`. | Reuse / Refactor | Preserve ordering; turn invalid arguments into an explicit error instead of silently changing them. |
| Attachments | Images become Anthropic base64 image blocks and PDFs become base64 document blocks for every endpoint/model. | Refactor | Gate by verified image/PDF capabilities and validate size/media/model constraints. |
| Stream parsing | Reads thinking, signature, redacted thinking, text and ordinary `tool_use`; ends only on `message_stop`. | Reuse / Gap | Preserve core events, add typed handling/evidence for server-tool/search and stop/error semantics. |
| Server search events | Provider server-tool/result/citation block variants are not explicitly modeled; unknown blocks are ignored. | Gap | Capture official fixtures and decide which events affect UI, continuation and terminal state. |

## Session continuation and terminal semantics

| Area | Current behavior | Classification | Required follow-up |
|---|---|---|---|
| State machine | Separates loading, reasoning, streaming, awaiting answer, done and error; reasoning never enters accepted Markdown. | Reuse | Keep this invariant and add explicit terminal classifications. |
| Clarification tool | `ask_clarifying_question` is the only app-owned tool; valid calls pause for user input and preserve Provider reasoning metadata. | Reuse | Preserve as a typed app-tool path. |
| Built-in search routing | A static name whitelist automatically continues `$web_search` and `plugin_web_search` whenever the user search preference is on, regardless of resolved Provider/protocol capability. | Contradiction | Replace names with typed Provider tool events/profile behavior. |
| MiniMax Anthropic | `plugin_web_search` and its Anthropic thinking metadata are replayed automatically. | Remove | MiniMax must use only its OpenAI-compatible path; delete the branch and its test. |
| Search loop bound | Automatic built-in search is limited to five turns per run and resets buffers between intermediate turns. | Reuse / Refactor | Keep a bounded loop, but bind it to verified Provider continuation semantics and preserve provenance. |
| Unknown tools | Unknown/invalid clarify calls end successfully if text exists, otherwise produce a generic “unrecognizable” error. | Refactor | Return typed, diagnosable terminal reasons and avoid silently accepting structurally invalid tool output. |
| Empty/reasoning-only result | The session reaches done and provides retry guidance; prior committed text is preserved. | Reuse / Refactor | Preserve data safety while making the empty/unknown/malformed distinction explicit. |
| Stop/retry/refine/regenerate | Partial content can be accepted; retry and regeneration retain safe history; refine rebuilds a document-edit request. | Reuse | Retain as regression coverage after client/profile changes. |

## Executable fixture and test inventory

| Suite / fixture | Current coverage | Classification | Missing coverage |
|---|---|---|---|
| `chat-reasoning-tool.sse` | OpenAI reasoning aliases, fragmented clarify tool call, ignored unknown field and `[DONE]`. | Reuse | Real Provider event variants, malformed JSON, error chunks, multiple choices/calls and interrupted streams. |
| `chat-text-only.sse` | Plain text and the invariant that literal `<think>` markup stays in final text. | Reuse | Usage/control terminal chunks and Provider-specific stop semantics. |
| `claude-thinking-tool.sse` | Thinking/signature plus fragmented ordinary tool use and message stop. | Reuse | Redacted block fixture, server search blocks/results/citations, errors and interruption. |
| `claude-text-only.sse` | Text deltas, ping and message stop. | Reuse | Empty/unknown terminal state fixtures. |
| Parser fixture tests | Four fixtures, Unicode, duplicate `[DONE]` suppression and high-frequency reasoning performance. | Reuse | Provider-labeled fixture matrix and negative/error cases. |
| Request contract tests | Baseline messages, date injection, generic image/PDF blocks, Claude continuation order and current search dialects. | Reuse / Rewrite | Endpoint/auth/header assertions; all ten Providers; exact search absence/presence; per-media capability; invalid configuration. |
| Config tests | Legacy field defaults, Responses migration and two labels. | Remove / Rewrite | Clean-break decoding, registry/default/detection/override and effective-capability resolution. |
| Session tests | Reasoning/body isolation, clarify continuation, Kimi and MiniMax search continuation, stop/retry/refine/regenerate and performance. | Reuse / Rewrite | Remove MiniMax Anthropic fixture; add typed Provider tools, loop limit, malformed/unknown/empty/interrupted terminal cases. |
| UI tests | No Provider/settings capability-state tests in `AIReasoningTests`. | Gap | Protocol-first layout, supported list, custom guidance, validation, accessibility, focus, language and capability explanations. |

Baseline verification on 2026-08-19: `MarkdownApp/AIReasoningTests/run-all.sh` passed ParserFixtureTests, RequestContractTests and SessionStateTests. The first sandboxed attempt failed only because Swift could not write the user-level Clang module cache; the same command passed with normal host cache access.

## S1.1 conclusion

The reusable core is the protocol-neutral message/event model, shared SSE pump, per-request date injection, reasoning/body isolation, ordinary function-tool serialization, Anthropic opaque thinking continuation, bounded session loops and the existing parser/session regression harness.

The redesign must remove or isolate four high-risk assumptions before claiming Provider support:

1. URL-driven protocol switching and protocol-only client creation.
2. GLM search syntax sent to every unrecognized OpenAI-compatible host.
3. Universal image/PDF serialization without Provider/model capability checks.
4. Third-party Anthropic and MiniMax `plugin_web_search` continuation.

S1.2 must therefore produce dated official evidence for endpoint/auth/stream/function-tool/search/attachment behavior and, equally importantly, explicit unsupported/unknown entries for every selected Provider.
