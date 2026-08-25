# Six-provider native AI contract

Verified: 2026-08-24

The production runtime supports exactly OpenAI, Anthropic, Gemini, Qwen, Kimi and GLM. Provider selection is explicit. A Base URL override changes only the host or regional prefix; it never changes Provider identity or wire format.

## Stable app boundary

`AIProviderAdapter` accepts app-domain messages, attachments and ordinary tools, then emits `AIStreamEvent`. Request bodies, stream envelopes, errors, file references and search call state remain private to each Provider module.

| Domain event | UI meaning | May enter accepted Markdown |
|---|---|---|
| `phase` | Connecting, thinking, searching, using a tool or generating | No |
| `reasoningDelta` / `reasoningBlock` | Provider-designated displayable reasoning | No |
| `search` | Search activity, continuation and normalized citations | No |
| `toolCall` | Completed ordinary app function call | No |
| `text` | Final answer delta | Only after a completed terminal state |
| `continuation` | Opaque Provider-owned state for the next turn | No |
| `usage` / `stopReason` | Accounting and terminal semantics | No |

Opaque signatures, encrypted content, thought signatures and Provider continuation payloads are never rendered. Answer text is never parsed for `<think>` or similar tags.

## Native routes

| Provider | Generation route | Search ownership |
|---|---|---|
| OpenAI | Responses `/v1/responses` | Hosted `web_search` |
| Anthropic | Messages `/v1/messages` | Versioned server tool |
| Gemini | Interactions `/v1beta/interactions` | Google Search grounding |
| Qwen | DashScope text/multimodal generation | Native search parameters and `search_info` |
| Kimi | Moonshot chat completions + Formula API | `moonshot/web-search:latest` Fiber continuation |
| GLM | BigModel chat completions | Native `web_search` chat tool |

No OpenAI Chat Completions compatibility route, host inference, custom Provider fallback or cross-Provider serializer is permitted. Qwen's compatible-mode path appears only in a fail-closed rejection guard and its negative contract test.

## Capability authority

`AIProviderManifest` is the only authority for advanced capability enablement. Exact model IDs and the `verifiedAt` date gate reasoning, search, image, PDF and file mechanisms. A successful model-list refresh proves account visibility only; a discovered but undocumented model remains fail-closed for advanced capabilities.

## Attachment and continuation invariants

- Direct image/PDF input, upload/reference, extraction and hosted retrieval remain distinct intents.
- Provider file references carry Provider identity and expiry metadata and cannot cross adapters.
- Unsupported, expired or oversized inputs fail during preflight; the app never silently drops or downgrades them.
- Hosted/server search never enters the ordinary client-tool loop. Only Kimi's typed built-in continuation follows its bounded Provider-owned path.
- Cancelled or interrupted partial text may be copied or retried, but cannot be accepted into the document.

## Regression evidence

`Fixtures/manifest.json` maps every Provider's request, stream, source, error, image, file and declared capability evidence. `run-all.sh` is the canonical offline regression entry point and includes manifest, localization, privacy and legacy-path audits.
