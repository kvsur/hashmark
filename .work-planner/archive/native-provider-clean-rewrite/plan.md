# Plan

## Architecture thesis

The app keeps one stable product experience while making each provider protocol explicit and independently testable:

```text
Unified AI Settings
└── AIConfig(provider, apiKey, model, endpointOverride, preferences)
                         │
                         ▼
AIProviderRegistry / dated capability manifest
└── exact provider + model + native-route capability resolution
                         │
                         ▼
AIProviderAdapter                         # coarse app-domain boundary only
├── OpenAIResponsesAdapter               # POST /v1/responses
├── AnthropicMessagesAdapter             # POST /v1/messages
├── GeminiAdapter                        # selected native Gemini route
├── QwenDashScopeAdapter                 # native text/multimodal generation
├── KimiAdapter                          # Moonshot native chat/files/tools
└── GLMAdapter                           # BigModel native chat/search
                         │
                         ▼
AIStreamEvent / AIGenerationPhase / AIResponsePresentationState
AISearchCitation / AIFileState / AIError
                         │
                         ▼
AIWritingSession → SwiftUI
```

The Adapter may normalize app concepts such as messages, attachments, search preference, text deltas, citations, tool state, usage and terminal outcome. It may not expose a shared Provider request body, shared SSE decoder, compatibility enum, host-derived identity, or a generic search continuation algorithm that assumes all server tools behave alike.

Suggested layout after the clean rewrite:

```text
Models/AI/
├── Core/
│   ├── AIProvider.swift
│   ├── AIProviderAdapter.swift
│   ├── AIRequest.swift
│   ├── AIMessage.swift
│   ├── AIStreamEvent.swift
│   ├── AIProviderCapabilities.swift
│   ├── AIProviderModelManifest.swift
│   ├── AISearchCitation.swift
│   ├── AIFileState.swift
│   └── AIError.swift
├── Providers/
│   ├── OpenAIResponses/
│   ├── Anthropic/
│   ├── Gemini/
│   ├── Qwen/
│   ├── Kimi/
│   └── GLM/
├── Attachments/
├── Diagnostics/
└── AIClientFactory.swift
```

Final names may follow Xcode group conventions, but each Provider directory owns transport, auth, request serialization, stream parsing, native tool events and file lifecycle. Files approaching 200-300 lines or mixing these responsibilities must be split.

## Dependency graph

```text
S1 → S2 ─┬→ S3 ─┬──────────────┐
         ├→ S4 ─┤              │
         ├→ S5 ─┤              ├→ S9 ──┐
         ├→ S6 ─┤              │       ├→ S11 ─┐
         ├→ S7 ─┤              ├→ S10 ─┘       ├→ S13
         ├→ S8 ─┘              │               │
         └→ S12 ───────────────┴───────────────┘
```

S3-S8 are independent Provider rewrites after the shared boundary in S2 and may be executed in parallel. S12 can begin from the stable config model while Provider clients are being built. S9 and S10 require all six Provider contracts so their normalized states do not accidentally privilege the first completed adapter. S11 consumes their attachment, search, reasoning and text events to complete the user-visible AIGC lifecycle.

## Phases / Steps

### S1 — Native contract freeze and demolition map

- Goal: Replace compatibility assumptions with a dated first-party contract matrix and an exact retain/rewrite/delete map before changing production code.
- Depends on: none
- Refs: C1 — final product boundary; C2/C3 — official research and user exploration; C4-C8 — current implementation and fixture assumptions; C11 — historical implementation decisions to explicitly supersede.
- Resolves: Gemini native route; Kimi search route; endpoint override rules; exact search-capable models/tool versions; native file lifecycles; any official SDK exception.
- Sub-steps:
  - S1.1 Inventory every current AI config, registry, factory, serializer, parser, tool continuation, attachment branch, UI dependency and fixture; mark retain, rewrite or delete.
  - S1.2 Reopen first-party docs for six providers and record dated endpoint, auth, model discovery, stream, reasoning, image, PDF/file and regional constraints.
  - S1.3 Freeze the Web Search matrix: exact supported models, tool name/version/schema, thinking conflicts, source/citation fields, server/client execution and continuation ownership.
  - S1.4 Freeze native file workflows and endpoint override policy, including direct blocks, upload IDs, extraction, hosted retrieval, expiry and cleanup.
  - S1.5 Produce the clean-break demolition map and lock REST-versus-SDK decisions; explicitly supersede every incompatible old decision.
- Verify: One reviewed matrix has six complete first-party contracts with dated sources and no compatibility route; every high-impact open item has a decision, and every old AI file/test family has an explicit retain/rewrite/delete disposition.

### S2 — Provider-neutral core and clean-break configuration

- Goal: Build a small stable domain boundary that routes explicit Provider identity without sharing wire payloads or retaining legacy protocol concepts.
- Depends on: S1
- Refs: C1/C2 — Adapter and model-manifest requirements; C4-C7 — current config/factory/session coupling; C9 — modularity, localization and privacy rules; C12 — generation phases and presentation event requirements; C13/C14 — frozen native contracts and demolition map.
- Sub-steps:
  - S2.1 Replace `APIProtocol`, ten-provider Registry, compatibility Adapter and custom Provider types with an `AIProvider` enum containing exactly six cases and a dated capability manifest.
  - S2.2 Define the coarse `AIProviderAdapter` interface for validation, request streaming, cancellation and optional file lifecycle operations; keep all wire types private to Provider modules.
  - S2.3 Define neutral `AIRequest`, message/content, attachment intent, search preference, stream event, citation, usage, continuation token, file state and terminal error models.
  - S2.4 Rebuild `AIConfig` and form state around explicit Provider selection while preserving the unified configuration flow; endpoint override never detects Provider or changes contract.
  - S2.5 Rebuild factory, structured diagnostics and privacy-safe correlation around the selected Provider; remove compatibility fallback and unsupported combinations before network access.
  - S2.6 Run native core/settings contract tests and a production-source audit for removed protocol, compatibility, host inference and shared wire paths.
- Verify: Core tests cover six providers, exact model capability resolution, invalid config and unknown models; production searches find no `APIProtocol`, custom/OpenAI-compatible fallback, host-based Provider inference or shared Provider wire payload.

### S3 — OpenAI Responses native adapter

- Goal: Replace OpenAI Chat Completions completely with the current Responses API and preserve all app writing/session actions.
- Depends on: S2
- Refs: C2/C13 — current Responses models/tool contract and frozen route; C5/C7/C8 — old OpenAI client, session behavior and fixture baseline; C12 — thinking/text/status stream events required by UI.
- Sub-steps:
  - S3.1 Implement official endpoint/auth, Responses input/instructions serialization, request options, cancellation and typed errors.
  - S3.2 Implement Responses streaming item/event parsing for reasoning, output text, custom tools, usage, refusal, errors and terminal state.
  - S3.3 Implement stateful/stateless continuation according to the S1 decision, preserving response IDs, reasoning items and any required opaque fields across retry/regenerate.
  - S3.4 Implement hosted `web_search` with exact model gates, tool choice, source inclusion and citation normalization.
  - S3.5 Implement image/file input plus the separately modeled upload/File Search lifecycle and add complete golden request/event fixtures.
- Verify: No OpenAI request targets `/chat/completions`; official Responses fixtures cover text, reasoning, custom tools, search with sources, image, direct file, File Search, cancellation and multi-turn continuation.

### S4 — Anthropic native adapter

- Goal: Rebuild Anthropic Messages as an independent Provider module using the selected current server-tool version and exact model capabilities.
- Depends on: S2
- Refs: C2/C13 — current Messages/web-search/PDF contract and frozen route; C5/C7/C8 — old Anthropic implementation and session fixtures; C12 — displayable versus opaque thinking and stream phase requirements.
- Sub-steps:
  - S4.1 Implement official endpoint, `x-api-key`, Anthropic version headers, Messages serialization, stream transport and typed API errors.
  - S4.2 Implement text, thinking/signature, redacted thinking, normal tool use/result, stop reasons, usage and exact continuation ordering.
  - S4.3 Implement the frozen `web_search_...` server tool version, supported-model gates, server tool events, citations and response-inclusion behavior.
  - S4.4 Implement image, inline PDF/document and Files API paths with media/size/model validation and lifecycle handling.
  - S4.5 Replace inherited fixtures with first-party request/stream/error fixtures, including older-tool rejection and unknown-model safety.
- Verify: Anthropic requests contain no OpenAI fields; selected tool version, thinking continuation, citations, images, PDFs/files and unsupported model paths match first-party fixtures.

### S5 — Gemini native adapter

- Goal: Implement the S1-selected Gemini native route with Google Search grounding, multimodal input, files and provider-owned conversation semantics.
- Depends on: S2
- Refs: C2/C13 — frozen Interactions, `google_search`, Files and grounding metadata; C7/C8 — app session and fixture requirements; C12 — native thought/text/search phase presentation events.
- Sub-steps:
  - S5.1 Implement the frozen native endpoint/auth/query/header contract and native content/role/system instruction mapping.
  - S5.2 Implement native streaming candidates/parts, thought data where exposed, function calls/results, safety outcomes, finish reasons and usage.
  - S5.3 Implement current `google_search` grounding with exact model gates; retain legacy `google_search_retrieval` only if S1 intentionally includes a supported older model.
  - S5.4 Parse grounding call/result metadata and citation spans into neutral citations without losing provider source identity.
  - S5.5 Implement inline/uploaded images, Files/PDF parts and separate File Search workflow with golden fixtures and lifecycle tests.
- Verify: Gemini never calls an OpenAI-compatible endpoint; native text/tool/search/image/file requests and stream/grounding fixtures pass for supported and rejected model combinations.

### S6 — Qwen DashScope native adapter

- Goal: Implement Qwen through native DashScope text and multimodal services, including their distinct streaming and search option contracts.
- Depends on: S2
- Refs: C2/C3/C13 — frozen native DashScope search and multimodal constraints; C7/C8 — app attachment/session and fixture requirements; C12 — multimodal upload/search/generation phase events.
- Sub-steps:
  - S6.1 Implement regional native DashScope endpoints, auth, text-generation input/parameters/output and model validation without compatible-mode URLs.
  - S6.2 Implement multimodal-generation content blocks and streaming separately from text Generation where the frozen model matrix requires it.
  - S6.3 Implement `enable_search` and `search_options`, including required streaming, `agent` strategy, force/source/citation/freshness/site options only on documented models.
  - S6.4 Normalize native `search_info` sources/citations and keep text/multimodal response events, reasoning and tools correctly separated.
  - S6.5 Implement native image/file/extract or retrieval workflows and add text, multimodal, search, attachment and rejection fixtures.
- Verify: No Qwen request uses `/compatible-mode/` or OpenAI schemas; native text and multimodal routes, search sources and file workflows match the dated DashScope matrix.

### S7 — Kimi native adapter

- Goal: Implement Moonshot/Kimi first-party chat, reasoning, search, vision and file lifecycles without reusing the OpenAI serializer/parser.
- Depends on: S2
- Refs: C2/C3/C13 — frozen Kimi K2.6 builtin search and file constraints; C7/C8 — session and fixture requirements; C12 — thinking visibility and search-thinking conflict UX.
- Sub-steps:
  - S7.1 Implement official Kimi endpoint/auth/model discovery and independent Kimi request/stream/error wire types.
  - S7.2 Implement K2.6 thinking and multi-step tool continuation with required `reasoning_content` preservation and parameter constraints.
  - S7.3 Implement the S1-selected search path: builtin `builtin_function.$web_search` with thinking disabled, or Formula `moonshot/web-search:latest` with encrypted output continuation.
  - S7.4 Normalize search sources/tool state and define explicit UX when the user's thinking preference conflicts with the selected search mechanism.
  - S7.5 Implement K2.6 image/video-relevant input boundaries, Files upload/reference and document extraction with complete fixtures and size/expiry handling.
- Verify: Kimi search never uses Qwen flags or generic OpenAI tool assumptions; K2.6 thinking/search conflict, continuation, images, uploaded files and extraction all have first-party fixtures.

### S8 — GLM native adapter

- Goal: Implement BigModel/Zhipu native chat and search contracts with exact separation between flagship text and visual/file-capable models.
- Depends on: S2
- Refs: C2/C3/C13 — frozen GLM-5.2 chat search and multimodal split; C7/C8 — session and fixture requirements; C12 — reasoning/search/text stream phase presentation events.
- Sub-steps:
  - S8.1 Implement official endpoint/auth, GLM message/request parameters, stream parsing, errors and model capability resolution.
  - S8.2 Implement thinking/reasoning, ordinary function tools, MCP/retrieval event rejection or support according to S1 scope, stop reasons and continuation.
  - S8.3 Implement the frozen default search path using chat `type: "web_search"` and provider-owned config, with standalone Web Search API only if S1 explicitly requires it.
  - S8.4 Parse top-level and streamed `web_search` source records into citations while preserving request IDs and source metadata.
  - S8.5 Implement exact visual/file model content blocks and document paths without assigning GLM-5.2 text-only capabilities by provider-level inference.
- Verify: GLM requests and source parsing match BigModel fixtures; text-only and visual/file model gates are explicit, and no OpenAI adapter or broad model substring participates.

### S9 — Native attachment and file lifecycle orchestration

- Goal: Give the shared UI one predictable attachment flow while preserving six distinct provider upload/input/extract/retrieval mechanisms.
- Depends on: S3, S4, S5, S6, S7, S8
- Refs: C2/C13 — six frozen file contracts; C7 — current attachment UI and local data flow; C9 — privacy and modularity constraints.
- Sub-steps:
  - S9.1 Replace the image/PDF boolean gates with typed attachment intents and states: local, validating, uploading, uploaded, extracting, ready, failed and expired.
  - S9.2 Implement provider-owned upload/reference/extract/retrieval operations behind optional Adapter capabilities, including cancellation, cleanup and retry idempotency.
  - S9.3 Centralize MIME, size, count, body-size and model checks without flattening provider limits; unknown combinations fail before upload or request.
  - S9.4 Preserve current text-context fallback only when explicit and visible; never silently downgrade PDF/file semantics or drop an attachment.
  - S9.5 Add privacy-safe attachment diagnostics and provider matrix tests for direct input, upload, reuse, expiry, extraction, retrieval, rejection and cancellation.
- Verify: Every selectable attachment has a deterministic native path or a preflight explanation; no provider receives another provider's file ID/block, and attachment data never appears in logs.

### S10 — Search citations, native tool state and session continuity

- Goal: Normalize user-visible search behavior and citations while each Adapter retains ownership of its native hosted/server/client tool lifecycle.
- Depends on: S3, S4, S5, S6, S7, S8
- Refs: C2/C13 — six frozen search contracts and citation shapes; C7 — current automatic search loop and writing actions; C8 — parser/session regression baseline; C12 — visible search/tool progress, cancellation and final-answer separation.
- Sub-steps:
  - S10.1 Replace generic automatic Web Search continuation with typed Provider-owned search events and continuation tokens; server-executed tools never enter a client loop.
  - S10.2 Define neutral search states and citations with title, URL, publisher, span/marker, query and provider source identity where available.
  - S10.3 Integrate citations into streaming/final writing output without contaminating accepted Markdown or duplicating source markers across retries.
  - S10.4 Rebuild stop, retry, regenerate, refine, clarify and multi-turn continuation around each Adapter's state rules, including reasoning/search/file opaque data.
  - S10.5 Add bounded-loop, malformed-event, source-less result, partial stream, cancellation, timeout and unknown-tool terminal tests plus privacy-safe timelines.
- Verify: Six search mechanisms produce consistent visible status/citations, but wire events and continuation remain provider-correct; all session actions preserve text/reasoning/source separation.

### S11 — End-to-end AIGC presentation and streaming UX

- Goal: Turn normalized Provider events into a complete, performant and recoverable generation experience from attachment preparation through final Markdown acceptance.
- Depends on: S9, S10
- Refs: C1/C13 — unified product experience and Provider event contracts; C7 — current writing view/session and attachment UI; C9 — accessibility/privacy constraints; C12 — explicit Thinking, streaming, scroll and interruption behavior.
- Sub-steps:
  - S11.1 Define one presentation state machine for idle, preparing attachments, uploading, connecting, thinking, searching, using a tool, generating, finalizing, completed, cancelled and failed.
  - S11.2 Implement a live Thinking panel that renders only user-displayable reasoning, auto-collapses when answer text begins, preserves manual user choice and never exposes opaque/signature data.
  - S11.3 Implement coalesced text/reasoning/source updates and incremental Markdown rendering that avoids per-token reparsing, flicker and excessive main-thread work.
  - S11.4 Implement reader-respecting auto-scroll, return-to-latest affordance, search/tool progress, incremental citation settlement and final answer-only Markdown acceptance.
  - S11.5 Implement coherent cancel/retry/regenerate behavior across transport/upload/UI animation plus explicit background, network interruption, partial response and malformed terminal states.
  - S11.6 Add deterministic presentation tests for phase transitions, reasoning/no-reasoning Providers, first-token behavior, scroll ownership, cancellation, interruption and accessibility announcements.
- Verify: All six adapters drive the same polished visible lifecycle without raw Provider branching; Thinking and streaming remain responsive, accessible and non-destructive, and only final answer text can enter the document.

### S12 — Unified settings, model freshness and capability UX

- Goal: Preserve one familiar configuration page while making six native Providers, current models and conditional capabilities understandable without protocol jargon.
- Depends on: S2
- Refs: C1 — unified-page requirement; C2/C13 — dynamic model/tool constraints and frozen defaults; C6 — current form and capability rows; C9 — i18n/accessibility rules.
- Sub-steps:
  - S12.1 Keep the current page hierarchy and common Key/model/endpoint/search controls, replacing obsolete protocol routing with explicit six-Provider selection and support copy.
  - S12.2 Make Provider defaults and endpoint regions available without showing raw request schemas; Base URL override remains advanced and cannot change Provider identity.
  - S12.3 Present dated model capability status for search/image/PDF/file/thinking conflicts, with unknown models safely disabled and clearly explained.
  - S12.4 Add model-list refresh where first-party APIs expose useful metadata, while keeping official dated capability rules authoritative for tool support.
  - S12.5 Update seven-language strings, focus/save/cancel behavior, Dynamic Type, VoiceOver, SF Symbols and UI state tests across all six Provider selections.
- Verify: Users configure all six through one page with no compatibility concepts or six technical forms; saved state routes exactly one native Adapter and capability explanations match the dated manifest.

### S13 — Contract regression, real-provider QA and handoff

- Goal: Prove the clean break across every native contract, app writing behavior, build mode and available live Provider account.
- Depends on: S11, S12
- Refs: C1/C2/C13 — final scope and dated contract; C8 — test target baseline; C9/C10 — i18n/build/device requirements; C12 — final Thinking/streaming/device acceptance criteria; C14 — final legacy-path absence audit.
- Sub-steps:
  - S13.1 Build a dated fixture manifest covering request, stream/event, source, error, image and file cases for all six Providers and every declared capability.
  - S13.2 Run core, Adapter, parser, session, attachment, presentation, settings, localization and privacy regression suites; audit that old compatibility types/routes/labels are absent.
  - S13.3 Run Debug and Release builds plus iPhone/iPad light/dark, Dynamic Type, VoiceOver, rotation, cancellation, backgrounding and weak-network QA.
  - S13.4 With available credentials, smoke-test each Provider's text, reasoning, normal tools, latest supported Web Search model, image and file path; record region/account prerequisites and doc-versus-runtime differences.
  - S13.5 Publish the final support/model/tool matrix, troubleshooting notes, untested items and future model-refresh procedure; audit every Definition of Done item.
- Verify: All offline contracts and builds pass, live-tested capabilities match the matrix, unavailable credentials are explicitly documented, and no legacy compatibility route remains reachable.

### S14 — Deterministic Web Search enforcement across six Providers

- Goal: Make the Web Search switch a deterministic per-turn execution contract across all six Providers, with Provider-native evidence and no keyword or model-choice fallback.
- Depends on: S13
- Refs: C8 — existing contract/session fixtures; C9 — i18n/privacy constraints; C15 — real-device regressions; C16 — dated first-party forced-search contracts; C17 — refreshed-model persistence regression; C18 — GLM-5.3 freshness and modality regression; C19 — Qwen 3.6–3.8 catalog and refresh regression.
- Sub-steps:
  - S14.1 Define the shared enforcement invariant and fail-fast behavior for unsupported model/tool combinations without sharing Provider wire payloads.
  - S14.2 Force hosted/server search for OpenAI Responses, Anthropic Messages and Gemini Interactions using each API's native tool-choice contract.
  - S14.3 Force Qwen with `forced_search`; keep Kimi on deterministic Formula preflight and remove keyword/continuation fallback.
  - S14.4 Add deterministic GLM Web Search API preflight, citation events and localized evidence-injection prompt before chat generation.
  - S14.5 Update six Provider fixtures, session/error/i18n/privacy regression, Debug/Release build and signed-device install.
  - S14.6 Preserve refreshed Provider model catalogs and the selected dynamic model across Settings reopen without treating programmatic load as a Provider switch.
  - S14.7 Refresh the GLM and Qwen dated manifests, model-specific native routes and search rules; make Qwen account-model discovery region-aware, diagnosable and covered by current first-party response fixtures.
- Verify: With Search on, every supported Provider request has a forced native search or preflight result and a search timeline; unsupported combinations fail before generation. With Search off, no search request or field is emitted. All contract/session/i18n/privacy tests and builds pass.
