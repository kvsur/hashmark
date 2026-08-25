# Native Provider Demolition Map

Frozen: 2026-08-24

## Delete in S2

| Old artifact | Disposition | Reason |
|---|---|---|
| Models/AI/APIProtocol.swift | delete | OpenAI/Anthropic protocol selection contradicts explicit six-Provider native routing |
| Models/AI/ProviderProfile.swift | delete | Encodes shared Chat/Messages adapters, auth and stream formats |
| Models/AI/ProviderRegistry.swift | delete/replace | Ten-provider host detection, compatible endpoints and request extensions are invalid |
| Models/AI/OpenAIChat/ | delete | Chat Completions compatibility is superseded by OpenAI Responses and independent native clients |
| Models/AI/Anthropic/ | delete | Old client is coupled to obsolete Profile; S4 rebuilds a private native module |
| AIConfig apiProtocol/providerOverride | delete/replace | Provider is explicit; endpoint override cannot infer identity |
| shared MultimodalContent, SSEEventParser, SSEStream | delete | They encode two-protocol wire assumptions |
| custom, xAI, DeepSeek, Mistral, MiniMax cases and UI copy | delete | Outside final support scope |

## Retain after neutralization

| Artifact | Retained responsibility | Required change |
|---|---|---|
| AIMessage | App-domain conversation history | Provider adapters map it privately |
| AITool and JSONValue | App custom tool schema | Provider adapters translate to native definitions |
| AIStreamEvent | Adapter-to-session events | add phase, citation, file and usage events |
| AIReasoningBlock | visible reasoning plus continuation | use Provider-scoped opaque continuation |
| AIWritingSession | writing actions and temporary event consumption | remove old Profile references; S10/S11 finish search/UI handling |
| AICapabilitiesSection | unified capability explanation | consume exact-model effective capabilities |
| AIConfigStore | local JSON persistence | clean-break decode rejects obsolete config |

## Add in S2

- Six-case AIProvider.
- Date-stamped AIProviderManifest and exact model rules.
- ResolvedAIProviderConfiguration with explicit Provider and native endpoint.
- Coarse AIProviderAdapter with no shared wire request/response types.
- Provider-scoped file reference/upload intent and neutral file state.
- Neutral generation phase, citations, usage and Provider continuation.
- Unified settings form driven by explicit Provider selection.
- Core/settings contract tests for six cases, native endpoints, exact model gates and absence of protocol UI.

## Deferred by design

- S3-S8 implement the six concrete native adapters.
- S9-S11 complete file lifecycle, typed search continuation and final streaming presentation.
- Old request/parser fixtures are obsolete after client deletion; each Provider phase replaces them with first-party fixtures before global regression.

