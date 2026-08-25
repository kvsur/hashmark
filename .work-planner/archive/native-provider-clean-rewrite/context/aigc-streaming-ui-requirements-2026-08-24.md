# AIGC Streaming and Thinking UI Requirements

Captured: 2026-08-24

## Trigger

The user asked whether the plan fully covers the end-to-end AIGC usage chain, especially final UI behavior for thinking and streaming.

## Gap found

The initial native-provider plan covered provider stream parsing, reasoning/text separation, search/tool state, citations, retries and cancellation. It did not give the final presentation layer its own phase or sufficiently explicit acceptance criteria. That left room for a technically correct transport implementation with an incomplete or unstable generation experience.

## Requirements added

- Model the full visible generation lifecycle: idle, preparing attachments, uploading, connecting, thinking, searching, using a tool, generating text, finalizing, completed, cancelled and failed.
- Provider adapters emit typed domain events. SwiftUI never branches on raw Provider event names or payloads.
- Display only reasoning content that the Provider explicitly returns as user-displayable reasoning. Never render signatures, encrypted blocks, opaque continuation tokens or fabricated chain-of-thought.
- While displayable reasoning is streaming, show a live Thinking panel. When answer text starts, collapse it by default while keeping a per-response user toggle. Do not override a user's manual expand/collapse choice.
- If a Provider exposes no reasoning text, show only a transient thinking/progress status when appropriate; do not fabricate a reasoning transcript.
- Search and tool activity have visible but non-technical progress. Citations may arrive incrementally and must settle without duplicating or contaminating accepted Markdown.
- Coalesce high-frequency deltas so Markdown does not reparse and relayout once per token. Preserve natural streaming latency without visible flicker or excessive main-thread work.
- Auto-scroll only while the reader is already near the bottom. Once the reader scrolls up, streaming must not pull the viewport away; provide an unobtrusive return-to-latest action.
- Cancellation must stop transport, upload and UI animation coherently. Retry/regenerate must follow Provider continuation rules and must not duplicate reasoning, sources, tool results or attachments.
- App backgrounding, network interruption, malformed events and partial terminal responses must end in an explicit recoverable state. Do not silently replay a non-idempotent Provider request.
- Only final answer text is eligible for insertion/acceptance into Markdown. Thinking, progress labels, sources and tool payloads remain presentation metadata.

