# Five-provider native AI contract

Verified: 2026-08-25

The production runtime supports exactly OpenAI, Anthropic, Gemini, Kimi and GLM. Provider selection is explicit. A Base URL override changes only the host or regional prefix; it never changes Provider identity or wire format.

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
| Anthropic | Messages `/v1/messages` | Versioned server tool; exact MiniMax official hosts use client-executed Coding Plan search |
| Gemini | Interactions `/v1beta/interactions` | Google Search grounding |
| Kimi | Moonshot chat completions + Formula API | `moonshot/web-search:latest` Fiber continuation |
| GLM | BigModel chat completions | Native `web_search` chat tool |

No OpenAI Chat Completions compatibility route, custom Provider fallback or cross-Provider generation serializer is permitted. Endpoint-specific extensions must be exact-host, typed contracts inside the selected Provider adapter; the sole current extension is MiniMax Coding Plan search while generation remains Anthropic Messages wire format.

## Capability authority

Each advanced capability is resolved independently in this order: explicit Provider metadata, exact Manifest rule, family Manifest rule, scoped runtime evidence, then conservative fallback. Image, PDF and generic-file input remain fail-closed while unverified. Native Web Search may make one explicit trial only when the user has enabled it, because its Provider protocol is already fixed; the result records scoped evidence without turning authentication, network, rate-limit or server failures into unsupported claims.

Model data, aliases, lifecycle and safe strategy IDs live in `Resources/AIProviders/manifest-v1.json`. Swift retains endpoint, authentication, request/stream, tool and file protocol code. Unknown models remain valid for text generation and saved selection.

## Attachment and continuation invariants

- Direct image/PDF input, upload/reference, extraction and hosted retrieval remain distinct intents.
- Provider file references carry Provider identity and expiry metadata and cannot cross adapters.
- Unsupported, expired or oversized inputs fail during preflight; the app never silently drops or downgrades them.
- Hosted/server search never enters the ordinary UI client-tool loop. Kimi Formula and MiniMax Coding Plan search execute inside their typed Provider adapters and return bounded Provider-owned results for synthesis.
- Cancelled or interrupted partial text may be copied or retried, but cannot be accepted into the document.

## Regression evidence

`Fixtures/manifest.json` maps every Provider's request, stream, source, error, image, file, decision and declared capability evidence. `run-all.sh` is the canonical offline regression entry point and includes Manifest/source governance, synthetic drift, localization, privacy, retired-Provider and legacy-path audits.
