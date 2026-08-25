# AI model maintenance runbook

Reviewed: 2026-08-25

This is the no-control-plane maintenance path for OpenAI, Anthropic, Gemini, Kimi and GLM. It keeps account discovery and local evidence separate from release-owned protocol changes.

## Authority and file map

| Concern | Authority |
|---|---|
| Model IDs, aliases, family inheritance, lifecycle, defaults, safe strategy IDs | `MarkdownApp/Resources/AIProviders/manifest-v1.json` |
| Manifest structure and allowed fields | `manifest-v1.schema.json` plus `AIModelManifestValidator` |
| Endpoint, auth, request/stream, native tool and file protocol | Provider-specific Swift modules |
| Account-visible model rows and metadata | Profile + Provider + normalized-endpoint catalog cache |
| Verified success or explicit unsupported result | Versioned capability evidence store |
| Frozen request/stream/search/attachment behavior | `Fixtures/manifest.json` and Provider contract tests |
| First-party documentation entry points | `Fixtures/official-sources.json` |

Never add a remote Manifest, CDN switch or API-key fingerprint. Never infer Provider identity from a custom Base URL.

## Provider metadata matrix

| Provider | Discovery and pagination | Metadata safe to consume | Deliberately unknown |
|---|---|---|---|
| OpenAI | `GET /v1/models`; current contract has no cursor | ID, created time, owner, shutdown date | Image, PDF, reasoning and search support |
| Anthropic | `GET /v1/models`; `last_id` to `after_id` | Explicit capability booleans, display name, release time, token limits | Missing/null capability fields |
| Gemini | `GET /v1beta/models`; `nextPageToken` to `pageToken` | Generation methods, thinking, version, description and token limits | Input modality or tool claims not explicitly returned |
| Kimi | `GET /v1/models`; ID-only conservative projection | ID, created time and owner when present | Advanced capability inference from catalog rows |
| GLM | No verified unified Models API | Reviewed Bundle Manifest and runtime evidence | Any invented `/models` route or guessed pagination |

Provider metadata beats local rules only when the field is explicit. An omitted field is not `false`.

## Snapshot and drift workflow

1. With an authorized account, capture a sanitized snapshot. The command reads `AI_PROVIDER_API_KEY`, never writes it, and performs only the Provider's Models API read:

   ```sh
   AI_PROVIDER_API_KEY=... zsh AIReasoningTests/capture-live-model-snapshot.sh openAI /tmp/openai-models.json
   ```

   `AI_PROVIDER_BASE_URL` is optional for an already-selected regional endpoint. GLM intentionally returns an unavailable error.

2. Compare it with the last reviewed snapshot:

   ```sh
   zsh AIReasoningTests/run-model-drift-audit.sh reviewed.json candidate.json
   ```

   Exit `0` means no drift, `2` means drift, and `64` means incorrect usage. The JSON report separates schema/protocol, added, missing, rename candidates, lifecycle and metadata changes.

3. Treat one missing catalog result as a candidate only. Do not remove a saved choice. Three consecutive successful misses may mark it deprecated; explicit Provider shutdown/deprecation can do so immediately.

4. Run `zsh AIReasoningTests/run-all.sh`. Synthetic drift fixtures prove every report category, and governance audit checks Provider coverage, source domains, fixture freshness and Manifest invariants.

## Cache and verification troubleshooting

| Symptom | Inspect | Safe action |
|---|---|---|
| Refresh failed or returned empty | HTTP/parser result and the scoped last-good snapshot | Keep last-good; do not save an empty catalog |
| Model disappeared once | Diff history and `missingCount` | Keep the model selectable and mark missing candidate |
| Capabilities differ after endpoint change | Profile ID and normalized endpoint | Expected isolation; verify again on the new endpoint |
| A search trial failed with 401/403/429/network/5xx | Evidence outcome and reason code | Keep it inconclusive; fix the operational problem |
| Search returned explicit model/tool unsupported | Sanitized status/body classification | Store unsupported evidence for that one capability and scope |
| Old success is ignored | Manifest version, protocol version and 30-day expiry | Re-verify; never copy evidence across versions or profiles |
| UI and request disagree | Selected catalog descriptor, saved Profile metadata and resolver source | Fix the data handoff; do not add a second capability gate |

## Change classification

| Observed change | Runtime/local action | App release |
|---|---|---|
| Added/missing model ID or ordinary metadata | Refresh cache, inspect diff, preserve last-good | No |
| New snapshot inside a declared family | Use family rule; verify advanced fields as needed | No |
| Search success/explicit unsupported on unchanged native protocol | Store scoped evidence | No |
| Exact exception, alias, default, lifecycle or family rule | Update Bundle Manifest and fixtures | Yes |
| Endpoint path, authentication or headers | Update typed Provider code and fixtures | Yes |
| Request/stream schema, search tool/version/citation/continuation | Update typed Provider code and full golden baseline | Yes |
| Upload/reference/extraction/retrieval protocol | Update Provider file service, attachment policy and cleanup tests | Yes |
| Provider removal or settings schema break | Product decision plus migration/removal audit | Yes |

If an upstream Provider genuinely removes a frozen capability, stop delivery and record it as an upstream breaking change. Do not hide it as a refactor or silently downgrade the request.

## Release checklist

- Run the complete offline suite and confirm all five frozen baselines pass.
- Validate `Localizable.xcstrings` and all six non-source locales for new UI text.
- Run privacy and retired-Provider residual audits.
- Build Debug and Release for simulator, plus a generic iOS device target without signing.
- Check Settings states for fresh, stale, missing candidate, deprecated, shutdown, custom and unverified capability source.
- When credentials are available, smoke-test only affected Provider reads/requests; never print keys, prompts, request bodies or attachments.
- Record unavailable credentials or physical-device checks explicitly instead of claiming they ran.
