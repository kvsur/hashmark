# S2a Hashmark privacy data-flow audit

Date: 2026-08-30

## Local documents and metadata

- Documents default to the app Documents directory.
- File timestamps are used locally for recent-activity display and sorting.
- Recovery copies live in Application Support and are excluded from backup where documented.
- Theme, language, storage mode, catalog/capability state, and AI consent scopes use app-local preferences or Application Support.

## iCloud

- iCloud Documents is opt-in and off by default.
- Apple synchronizes the public `iCloud.com.kvsur.MarkdownApp` document container.
- Disabling sync downloads and verifies a local copy; it does not delete the cloud copy.

## AI configuration and transmission

- Provider profiles and API keys are stored in the app's Application Support directory.
- Supported recipients are OpenAI, Anthropic, Google Gemini, Moonshot Kimi, and Zhipu GLM; users may override the endpoint for the selected native provider protocol.
- Generation requests may transmit API credentials, prompts, selected/document context, follow-up answers, model identifiers, and optional provider-native web-search queries.
- Explicitly selected images, camera photos, PDFs, text files, and Hashmark documents may be sent inline or uploaded to the selected provider.
- Requests go directly from the device to the configured provider/endpoint; Hashmark has no developer-operated proxy.
- The attachment lifecycle attempts to release temporary remote file references, but provider retention remains governed by the provider.
- Debug diagnostics record provider/host/path/status/counts and byte/character counts, not prompt, document, attachment content, API keys, raw streams, or tool arguments.

## System access

- Camera access is user initiated for an AI attachment.
- Photo selection is user initiated; photo-library add access is used when saving an exported long screenshot.
- File/document selection is user initiated.

## Developer-operated collection

- No developer account system, analytics SDK, advertising SDK, tracking domain, crash-reporting SDK, or Hashmark server was found.
- Apple may process iCloud, TestFlight, App Store, and system diagnostics under Apple's own policies.

## Required release controls

- Publish a no-login HTTPS privacy policy and link it from App Store Connect.
- Add an easy-to-find in-app policy link.
- Obtain explicit consent before the first connection to each Provider + Endpoint recipient.
- Treat a changed recipient as a new scope, allow withdrawal, and block production AI client creation without current consent.
