# Plan

## Architecture thesis

The app exposes a deliberately small product surface while keeping protocol differences explicit internally:

```text
AIConfig
├── apiProtocol: OpenAI | Anthropic       # user-visible, exactly two choices
├── provider: AIProvider                  # detected or explicitly resolved
└── preferences: web search / attachments # user intent, not capability truth
             │
             ▼
ProviderRegistry
├── endpoint/auth profile
├── protocol request shape                # Chat Completions / Messages only
├── capability profile                    # function/search/image/pdf/file/reasoning
└── server-tool continuation policy
             │
             ▼
AIClientFactory
├── OpenAIClient + Provider Chat adapters
└── AnthropicClient (official only)
             │
             ▼
AIStreamEvent → AIWritingSession → SwiftUI
```

`AIProvider` identifies OpenAI, Anthropic, Gemini, xAI, DeepSeek, Qwen, Mistral, Kimi, GLM, MiniMax, or custom OpenAI. `APIProtocol` never encodes a provider name. `ProviderCapabilities` is the only source of truth for whether a feature may be serialized; views may explain capability but may not invent it. Provider-specific wire data stays below the neutral event layer.

Suggested feature layout after refactor:

```text
Models/AI/
├── AIConfig.swift
├── APIProtocol.swift
├── AIProvider.swift
├── ProviderProfile.swift
├── ProviderRegistry.swift
├── AIClient.swift
├── OpenAIClient.swift
├── AnthropicClient.swift
├── Adapters/
│   ├── OpenAIChatRequestAdapter.swift
│   ├── ProviderSearchAdapter.swift
│   ├── ProviderToolAdapter.swift
│   └── ProviderAttachmentAdapter.swift
└── Diagnostics/AIDiagnostics.swift

Features/Settings/
├── AIConfigEditorView.swift
├── AIProtocolSection.swift
├── AIEndpointSection.swift
└── AICapabilitySection.swift
```

Final names may follow the existing Xcode group style, but responsibilities must remain separated and files near the 200–300 line threshold must be split.

## Dependency graph

```text
S1 → S2 ─┬→ S3 ───────────────┐
         ├→ S4 ─┬→ S6 ─┐      │
         └→ S5 ─┘       ├→ S8 ├→ S9 → S10A → S10
                └→ S7 ──┘      │
```

S3, S4, and S5 may start independently after S2. S6 and S7 share the stabilized transport clients. S9 begins only when UI and runtime paths converge. S10A reconciles the post-freeze Provider documentation before any live S10 acceptance work.

## Phases / Steps

### S1 — Provider contract audit and decision freeze

- Goal: Replace assumptions with a signed-off matrix covering transport, endpoint, auth, streaming, reasoning, function tools, server search, tool continuation, images, PDFs and files for all ten selected providers plus custom OpenAI.
- Depends on: none
- Refs: C1 — product boundary and failure sample; C2 — research snapshot and official links; C3–C9 — current assumptions embedded in code/tests; C12 — current implementation audit; C13 — reviewed contract matrix and frozen decisions.
- Resolves: Provider selection UX; Provider-specific Chat Completions extensions; Anthropic endpoint locking; unsupported-capability UI; model-level rules.
- Sub-steps:
  - S1.1 Inventory every current protocol/host/capability branch, endpoint builder, request field, parser event, session continuation and test fixture; mark dead, reusable and contradictory behavior.
  - S1.2 Revalidate official documentation for OpenAI, Anthropic and eight third-party providers; record dated endpoint/auth/stream/tool/search/file contracts and confidence level.
  - S1.3 Lock the Provider adapter table inside OpenAI SDK-compatible Chat Completions: standard endpoint/request baseline plus verified auth, search, tool-continuation and attachment extensions. Responses is explicitly excluded.
  - S1.4 Lock UX decisions for Provider detection/override, official Anthropic endpoint, unavailable capabilities and user preference persistence; update the plan if user choice changes dependencies.
- Verify: One reviewed contract table has no provider mapped to an undocumented wire shape; every open item in Summary has a decision or a named execution-time validation.

### S2 — Domain model, Provider Registry and clean-break configuration

- Goal: Establish one compile-time source of truth that separates API protocol, Provider identity, Provider adapter and effective capabilities, without legacy configuration migration.
- Depends on: S1
- Refs: C1, C2, C13 — required provider boundary and frozen contracts; C3, C5–C8 — current config/factory/session coupling; C10 — modularity rules.
- Sub-steps:
  - S2.1 Replace `ResponseFormat` with `APIProtocol.openAI/.anthropic`; rename public/internal labels and remove `chatGPT`, `claude`, `openAIResponses`, URL format suggestion and old decoding migration paths.
  - S2.2 Add `AIProvider`, Provider Adapter and capability types whose states distinguish unsupported, supported, conditional/model-specific and separate-service-only behavior.
  - S2.3 Implement a centralized `ProviderRegistry` for official domains, default Chat Completions endpoints, auth headers, verified request extensions, model constraints and capabilities; unknown URLs resolve to `customOpenAI` conservatively.
  - S2.4 Define configuration validation and effective-capability resolution as pure testable logic; user preferences remain separate from registry truth.
  - S2.5 Update `AIClientFactory` and call sites to consume the resolved profile; prevent Anthropic protocol from resolving to non-Anthropic providers.
- Verify: Model tests cover all Provider/domain mappings, invalid combinations, unknown endpoints and default values; a repository search finds no runtime dependency on legacy response-format values or scattered provider host switches.

### S3 — Protocol-first settings and explicit Provider support guidance

- Goal: Make the form explain the product model and the exact ten-provider support promise before endpoint details, while preventing users from saving combinations the runtime will reject.
- Depends on: S2
- Refs: C1, C13 — required order, copy intent and locked Provider/capability UX; C4 — current form; C10 — i18n/accessibility requirements.
- Sub-steps:
  - S3.1 Move the `OpenAI / Anthropic` segmented selection to the first section, rename it API Protocol, and remove Base URL focus-driven format switching.
  - S3.2 Implement protocol-dependent endpoint fields: official Anthropic endpoint behavior from S1; editable OpenAI-compatible Base URL/model/API Key; API Key remains a normal text field.
  - S3.3 Add a persistent, non-technical support notice that names all ten officially supported Providers. Group OpenAI, Gemini, xAI, DeepSeek, Qwen, Mistral, Kimi, GLM and MiniMax under the OpenAI path, and Anthropic under the official Anthropic path.
  - S3.4 Explicitly label unknown custom OpenAI-compatible endpoints as best-effort compatibility rather than part of the official ten-provider support promise.
  - S3.5 Present detected/selected Provider and validation feedback without turning the form into an SDK console; support the S1 provider-override decision for gateway/custom URLs.
  - S3.6 Rework Web Search and attachment rows to show user preference plus current availability/reason, with Web Search preference default on and unsupported capabilities never silently sent.
  - S3.7 Add VoiceOver, Dynamic Type, keyboard, focus, validation and save/cancel tests; update all affected strings—including all ten Provider names and support-boundary copy—in seven supported languages with no emoji.
- Verify: UI/state tests and iPhone/iPad inspection prove protocol is first, only two protocol labels exist, all ten officially supported Providers are explicitly visible, custom compatibility is not presented as official support, invalid combinations cannot save, capability states are understandable, and language/accessibility layouts remain stable.

### S4 — OpenAI-compatible Chat Completions core and Provider adapters

- Goal: Replace the provider-by-host logic inside `ChatGPTClient` with one neutral OpenAI SDK-compatible Chat Completions client and explicit, testable Provider adapters; never switch a Provider to Responses.
- Depends on: S2
- Refs: C2, C13 — provider contracts and exact adapter allowlist; C5, C6 — shared SSE and existing OpenAI serializer/parser; C9 — fixture baseline.
- Sub-steps:
  - S4.1 Rename/split `ChatGPTClient` into `OpenAIClient` with one Chat Completions request/stream core shared by all nine OpenAI-side Providers.
  - S4.2 Centralize endpoint completion, Bearer/auth variations, headers, model and streaming options in Provider Profiles rather than URL checks inside serialization.
  - S4.3 Port ordinary messages, reasoning deltas, function calls, tool results, cancellation and no-content completion from Chat Completions into the normalized `AIStreamEvent` contract.
  - S4.4 Implement provider adapters for OpenAI, Gemini, xAI, DeepSeek, Qwen, Mistral, Kimi, GLM and MiniMax only where the audited contract differs from the base adapter.
  - S4.5 Preserve system date/time injection exactly once per actual request/continuation and ensure fallback/retry cannot duplicate it in history.
- Verify: Golden Chat Completions request and SSE fixture tests pass for every Provider adapter; unknown custom endpoints emit only baseline fields; repository and request tests prove no runtime Responses path exists.

### S5 — Official Anthropic transport hardening

- Goal: Keep one first-class Anthropic Messages path with official endpoint semantics, reasoning continuity, server tools and attachment serialization, while removing third-party proxy accommodations.
- Depends on: S2
- Refs: C1 — official-only decision and MiniMax failure; C2, C13 — Anthropic contracts and endpoint lock; C5, C7–C9 — current client/parser/session/tests.
- Sub-steps:
  - S5.1 Rename/split `ClaudeClient` to provider-neutral product naming such as `AnthropicClient`, and enforce the official endpoint/header/version contract chosen in S1.
  - S5.2 Preserve text, thinking/signature/redacted blocks, ordinary tool use/result and streaming stop reasons through normalized events and exact continuation serialization.
  - S5.3 Remove third-party Anthropic assumptions and tests, including MiniMax `plugin_web_search` as a supported Anthropic route; retain a generic diagnostic path for unknown tools.
  - S5.4 Keep server Web Search and image/PDF support behind Anthropic's verified capabilities, model restrictions and user preferences.
- Verify: Official Anthropic golden requests and stream fixtures pass for text/reasoning/tools/search/attachments; non-official Anthropic configuration is rejected before network access; MiniMax is reachable only through OpenAI routing.

### S6 — Server-side Web Search capability matrix

- Goal: Make Web Search predictable across providers: supported request shapes work, built-in tool round trips continue safely, and unsupported/unknown endpoints receive nothing.
- Depends on: S4, S5
- Refs: C1 — default-on behavior and failure; C2, C13 — provider search contracts, exact wire forms and continuation policy; C6–C9 — existing host-specific request extensions, continuation and tests.
- Sub-steps:
  - S6.1 Model search mechanisms explicitly inside the two supported APIs: Chat Completions request option/field/tool, Chat built-in tool continuation, and Anthropic server tool. Responses, Agent, MCP and native-SDK-only services are outside scope.
  - S6.2 Implement audited search serializers/parsers for OpenAI and Anthropic plus only those OpenAI-compatible providers confirmed in S1 (expected candidates: xAI, Qwen, Kimi and GLM).
  - S6.3 Mark any Provider route unsupported or conditional when search exists only through Responses, a native SDK, Agent or MCP instead of its verified Chat Completions contract; do not substitute those APIs silently.
  - S6.4 Gate effective search on preference + Provider capability + model/Chat-adapter constraints; emit a structured decision log and user-facing availability reason.
  - S6.5 Bound automatic built-in search continuations, preserve provider-owned call identifiers/arguments without exposing them, and stop loops deterministically.
- Verify: Per-provider request fixtures prove exact presence/absence of search fields; continuation, citation/text arrival, max-turn and disabled/unsupported tests pass; no unknown endpoint receives GLM/Kimi syntax by default.

### S7 — Image, PDF and file capability matrix

- Goal: Stop treating every OpenAI-compatible endpoint as accepting the same data-URI blocks and route only attachment forms verified for the selected Provider/model/Chat adapter.
- Depends on: S4, S5
- Refs: C1, C2, C13 — file capability requirement, provider snapshot and frozen attachment forms; C6, C7 — current serializers; C8, C9 — session and regression tests.
- Sub-steps:
  - S7.1 Split capability vocabulary into inline image, inline PDF/document, uploaded file reference, retrieval/file search and text-context fallback.
  - S7.2 Audit and implement exact inline attachment serializers for official OpenAI/Anthropic and the verified subset of third-party OpenAI-compatible providers.
  - S7.3 For providers requiring upload or a separate library workflow, either implement a bounded adapter approved by scope or mark the feature unavailable; never upload implicitly to an unrelated retention service.
  - S7.4 Make the picker/UI honor effective capabilities before attachment selection and revalidate before the request; preserve existing local text-document context fallback.
  - S7.5 Add size/type/model validation and privacy-safe diagnostics without logging attachment bytes or extracted content.
- Verify: Request fixtures cover supported image/PDF/file shapes and every unsupported rejection; no attachment is silently dropped or serialized in a guessed format; existing text-reference behavior passes regression.

### S8 — Session continuity, error semantics and privacy-safe diagnostics

- Goal: Ensure provider-owned reasoning/search/tool events cannot collapse into “unrecognized content” without enough structural evidence to diagnose and retry safely.
- Depends on: S6, S7
- Refs: C1, C13 — observed failure, provider continuation and logging requirements; C5, C8 — diagnostics and session state; C9 — parser/session tests.
- Sub-steps:
  - S8.1 Replace the static session tool-name allowlist with typed provider tool events/continuation policies produced by adapters; ordinary app tools remain separate.
  - S8.2 Define terminal outcomes for reasoning-only, search-only, empty message, unknown tool, malformed SSE, interrupted stream and provider stop reasons while preserving partial valid text.
  - S8.3 Add a correlation identifier and structured Debug timeline for protocol/provider/adapter, effective capabilities, HTTP/SSE structure, tool transitions, fallback and final outcome.
  - S8.4 Audit logs for secrets and user content; keep payload shape/byte counts and field names only, and make Release logging a no-op where appropriate.
  - S8.5 Revalidate stop/retry/regenerate/refine/clarify/automatic-search flows so provider transport metadata persists only as long as its continuation requires.
- Verify: Failure-injection tests reproduce the historical MiniMax pattern and now yield the intended OpenAI route or a precise structural error; log snapshots are actionable and contain none of the banned sensitive fields.

### S9 — Full contract, regression and build matrix

- Goal: Prove the new abstraction is coherent across model, UI, request, parser and session layers before manual provider testing.
- Depends on: S3, S8
- Refs: C1–C13 — complete requirements, frozen contracts, code baselines, tests and build entry points.
- Sub-steps:
  - S9.1 Build a provider fixture manifest that maps every supported capability to official documentation date, request fixture, response/SSE fixture and expected normalized events.
  - S9.2 Add model/registry/config/UI state tests for defaults, detection/override, invalid Anthropic endpoints, custom OpenAI, capability reasons and removal of legacy migration.
  - S9.3 Expand parser/session tests for the two supported API forms—OpenAI-compatible Chat Completions and Anthropic Messages—including fragmentation, Unicode, usage/control chunks, server tools, unknown tools, cancellation and partial failures.
  - S9.4 Regress API Key text display, dynamic date/time, ordinary function tools, reasoning isolation, attachments, clarify, stop, retry, refine, regenerate and accepted Markdown.
  - S9.5 Run focused tests, complete test suite, static repository audits, and Debug/Release simulator builds; resolve warnings introduced by this work.
- Verify: Fixture manifest has no unsupported claims, all tests/builds pass, legacy types/labels/host switches are absent, localization catalog has no missing supported-language values, and workspace changes remain scoped.

### S10A — Post-freeze capability reconciliation and implementation correction

- Goal: Reconcile the 2026-08-23 Web Search/image findings with the frozen matrix and local implementation, then repair direct Chat-path mismatches before live acceptance.
- Depends on: S9
- Refs: C13, C14, C15 — old freeze, fixture manifest, and newly consolidated official evidence.
- Sub-steps:
  - S10A.1 Consolidate the supplied official sources and classify every capability as direct Chat path, alternative API path, model-conditional, unsupported, or unconfirmed.
  - S10A.2 Produce a dated reconciliation matrix for Kimi/Qwen/GLM search, conditional image inputs, and MiniMax/xAI/Gemini/DeepSeek boundaries; update C13/C14 through a new superseding artifact rather than rewriting history.
  - S10A.3 Audit Provider Registry, serializers, stream parsers, session continuation, capability UI and fixtures against the reconciled matrix; record exact mismatch locations.
  - S10A.4 Repair direct Chat-path mismatches and add request/response/session regression fixtures; do not add alternative API families without an explicit product decision.
- Verify: Every supplied claim is mapped to an official wire contract and a local behavior; Kimi/Qwen/GLM direct Chat search and supported image paths have fixtures, while alternative/unsupported paths send nothing and explain why.

### S10 — Real-provider smoke tests, device QA and handoff

- Goal: Validate the plan's contracts against available live services and leave an honest support matrix future maintainers and users can rely on.
- Depends on: S10A
- Refs: C1, C2, C13, C15 — user intent, original matrix, corrected capability-path evidence and execution-time validation boundary; C4, C10, C11 — UI, localization/accessibility and Xcode device workflow.
- Sub-steps:
  - S10.1 Run privacy-safe live smoke tests for every Provider with available credentials: text stream first, then reasoning, function tool, Web Search and attachment capabilities individually.
  - S10.2 Record unavailable credentials, region/model restrictions, billing/feature prerequisites and mismatches between docs and live responses; downgrade capability profiles rather than guessing.
  - S10.3 Verify configuration, success, unsupported capability and failure states on iPhone/iPad in light/dark mode, Dynamic Type, VoiceOver, rotation and poor-network/cancellation scenarios.
  - S10.4 Validate Xcode Console and device-log troubleshooting instructions using correlation IDs without exposing secrets/content.
  - S10.5 Update in-repo support documentation and the dated Provider matrix, then complete final scope/diff/DoD review.
- Verify: Available live providers pass their advertised matrix; unavailable ones retain fixture-backed status explicitly marked as not live-tested; device/accessibility/build checks and all Definition of Done items are signed off.
