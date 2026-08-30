# Plan — iOS 16 Compatibility and Optional iCloud Documents Sync

## Target Architecture

- `DocumentLibraryController` is a `@MainActor ObservableObject` injected once at the app root. It publishes the committed storage mode, aggregate cloud/migration state, active library identity, and refresh revision.
- `DocumentLibraryService` is an actor and the only runtime owner of document I/O. Views no longer create `FileStore()` directly; they call async library operations through the controller.
- `FileStore` remains the low-level, testable path/CRUD engine, but receives explicit active-root and local-Inbox URLs plus a file-access coordinator. Cloud operations use `NSFileCoordinator`; local tests can use a direct coordinator.
- `ICloudContainerService` resolves `iCloud.com.kvsur.MarkdownApp` off the main thread, observes identity changes, owns the `Documents` container URL, starts downloads, and supplies aggregate availability/sync state.
- `ICloudLibraryPresenter` and metadata monitoring convert external add/change/move/delete/download/conflict events into library revisions. `ICloudConflictResolver` preserves distinct versions before marking/removing resolved `NSFileVersion` entries.
- `DocumentMigrationService` uses an Application Support journal and recovery backup. Storage preference commits only after verification, so crash recovery can deterministically resume or roll back.

## Public Types and Behavioral Contracts

- `DocumentStorageMode: String, Codable` has `.local` and `.iCloud`; persisted mode changes only at migration commit.
- `DocumentLibraryState: Equatable` covers local-ready, checking-cloud, cloud-ready/syncing, migrating(direction/progress), cloud-unavailable, and failed states. Settings renders this state; browser rows do not add badges.
- Document reads become throwing/async and distinguish empty content, not-downloaded, unavailable, missing, and I/O failure. Writes, moves, renames, imports, and deletes are coordinated and atomic.
- Enable transaction: validate account/container → freeze mutations → snapshot and back up local library → merge into cloud → verify → commit cloud mode → clean local originals except Inbox → retain recovery backup until upload confirmation.
- Disable transaction: validate cloud access → freeze mutations → download every item → merge/verify into local Documents → commit local mode → unregister active cloud monitoring. Cloud files are never deleted or evicted as part of disabling.
- Merge contract: match by relative path; merge folders; skip byte-identical files using SHA-256; preserve incoming divergent/type-collision items with a localized timestamped conflict-copy name; never overwrite distinct content.
- Crash contract: before commit, launch resumes or rolls back while retaining the old mode; after commit, launch uses the new mode and completes cleanup. Re-running any phase is idempotent.

## Dependency Graph

`S1 → S2 → S3 → S4 → S5 → S6 → S7`

## Phases / Steps

### S1 — Freeze current behavior and compatibility inventory

- Goal: establish a zero-regression baseline and a complete iOS 16/iCloud impact map before structural changes.
- Depends on: none
- Refs: C1, C2, C3, C4, C6, C7, C12, C13 — requirements, current storage/build/observation/lifecycle, tests, historical intent, and the completed freeze report.
- Sub-steps:
  - S1.1 Run and record every existing script suite plus Debug/Release simulator and unsigned device builds on the committed baseline.
  - S1.2 Freeze local CRUD, nested ordering, import/Inbox, move/rename/delete, preview/edit/save, AI document-reference, and external-open behavior in regression tests.
  - S1.3 Capture the iOS 16 compiler audit: Observation/environment usage, all two-argument `onChange` calls, empty-state APIs, scroll anchoring, and iOS 16.4 presentation modifiers.
  - S1.4 Map every direct `FileStore()` construction and URL-identity assumption that must consume the active library.
  - S1.5 Define fault-injection seams for container failure, download failure, copy/write/delete failure, crash checkpoints, external change, and version conflict.
- Verify: baseline tests/builds pass, every affected entry point is mapped, and later phases have executable regression/fault scenarios rather than prose-only guarantees.

### S2 — Backport the application to iOS 16.0

- Goal: make the unchanged local-only application compile and behave on iOS 16 before introducing cloud storage.
- Depends on: S1
- Refs: C1, C3, C4, C5, C6, C13, C14 — requested compatibility floor, current app observation/UI lifecycle, availability inventory, and completed backport evidence.
- Sub-steps:
  - S2.1 Convert `SettingsStore` to `ObservableObject/@Published`, own it with `@StateObject`, and distribute it through `environmentObject`/`@EnvironmentObject`.
  - S2.2 Convert `AIWritingSession` to `ObservableObject`, publish only UI-observed state, keep stream coalescing non-published, and replace session reassignment with an idle-only reconfiguration method compatible with `@StateObject`.
  - S2.3 Replace all iOS 17 `onChange` overloads with iOS 16 forms; explicitly track the previous AI phase and pair initial theme application with `onAppear`.
  - S2.4 Add one reusable iOS 16 empty-state view and a bottom-following reasoning scroll implementation; preserve existing labels/actions/accessibility and use native newer behavior only behind centralized availability branches.
  - S2.5 Centralize iOS 16.4 sheet/popover modifiers with default iOS 16.0–16.3 presentation fallback; retain iOS 26 Liquid Glass and extend its documented fallback range to iOS 16–25.
  - S2.6 Set both project configurations to `IPHONEOS_DEPLOYMENT_TARGET = 16.0`, keep the latest Base SDK, update minimum-version documentation, and run the availability audit plus full baseline.
- Verify: local-only Debug/Release builds target iOS 16.0 without unguarded availability errors; all frozen behavior and current newer-OS builds pass.

### S3 — Centralize the document library and preserve local behavior

- Goal: remove ad-hoc root discovery and establish one async, mode-aware document API without changing local results.
- Depends on: S2
- Refs: C1, C2, C6, C7, C9, C13, C14 — storage semantics, lifecycle, frozen tests/URL identities, iOS 16 patterns, and coordinated-access requirement.
- Sub-steps:
  - S3.1 Introduce `DocumentStorageMode`, `DocumentLibraryState`, persisted preference storage, `DocumentLibraryService` actor, and root `DocumentLibraryController` environment ownership.
  - S3.2 Refactor `FileStore` to require explicit active root and a separate local `Documents/Inbox` URL; keep Inbox hidden/purged locally in both storage modes.
  - S3.3 Add direct and coordinated file-access implementations; make reads throwing and writes atomic so empty files cannot be confused with failures.
  - S3.4 Expose async scan/tree/read/write/create/import/move/rename/delete APIs from the library service and serialize mutations during transitions.
  - S3.5 Rewire browser, document, import, switcher, outline, preview/share, and AI reference flows to the injected library; remove runtime `FileStore()` construction.
  - S3.6 Add local-mode actor/controller and UI lifecycle tests, including mode-identity navigation reset and unsaved-save behavior.
- Verify: with mode fixed to local, every S1 baseline passes and all document I/O flows through the centralized service without main-thread file scans.

### S4 — Add iCloud Documents capability and cloud runtime

- Goal: establish signed container access, coordinated cloud I/O, on-demand download, external-change monitoring, and aggregate status without enabling migration yet.
- Depends on: S3
- Refs: C1, C3, C8, C9, C10, C13, C14 — product rules, signing configuration, Apple container/coordination/presenter contracts, fault seams, and iOS 16 compatibility patterns.
- Sub-steps:
  - S4.1 Register/validate `iCloud.com.kvsur.MarkdownApp`, add the Cloud Documents entitlements and target capability, and declare a public document-scope `NSUbiquitousContainers` entry named Hashmark.
  - S4.2 Resolve the ubiquity container on a background executor, create/use its `Documents` directory, check identity changes, and never call the resolver on the main thread.
  - S4.3 Implement coordinated cloud CRUD and atomic replacement while preserving directory hierarchy, Markdown filtering, Files app access, and security-scoped imports.
  - S4.4 Implement on-demand download and typed readiness/errors; downloaded items work offline, while unavailable cloud-only items wait with retry/cancel behavior rather than reading as empty.
  - S4.5 Register a root `NSFilePresenter` plus metadata monitoring for external add/change/move/delete and upload/download/error state; publish only aggregate state to Settings.
  - S4.6 Add fake-container/presenter/metadata tests and a signed single-device smoke test that never touches the user's local library.
- Verify: a test document round-trips through the real container and Files app, external changes refresh the library, offline downloaded access works, and account/container failure is typed and non-destructive.

### S5 — Implement the iCloud switch and transactional migrations

- Goal: deliver the exact enable/disable/re-enable semantics with crash safety and no destructive overwrite.
- Depends on: S4
- Refs: C1, C5, C8, C11, C13, C14 — locked switch behavior, Settings pattern, container availability, conflict cleanup, crash/I/O scenarios, and iOS 16 UI patterns.
- Sub-steps:
  - S5.1 Implement versioned migration snapshots/journal/checkpoints and an Application Support recovery backup excluded from both visible document roots.
  - S5.2 Implement recursive relative-path merge with folder merge, SHA-256 identical-file dedupe, deterministic timestamped conflict-copy naming, and file/folder collision handling.
  - S5.3 Implement enable: validate → freeze → back up → merge local to cloud → verify → commit cloud mode → remove local originals except Inbox; retain recovery backup until upload confirmation.
  - S5.4 Implement disable: validate → download all → merge/verify cloud to local → commit local mode; leave every cloud item untouched and fail without switching if a complete local copy cannot be proven.
  - S5.5 Implement launch recovery and idempotent retry for interruption before/after commit, plus iCloud identity-change handling that keeps the committed mode and blocks unsafe mutation.
  - S5.6 Add a Settings Documents section with an intercepted switch, enable/disable confirmations, progress, aggregate account/sync/error status, retry, and the defined disabled state while transitioning.
  - S5.7 Add/translate every new user-visible string in 简中/英/繁中/日/韩/德/俄 and cover VoiceOver, Dynamic Type, cancellation, and error recovery.
- Verify: exhaustive temporary-root and injected-failure tests prove no lost/overwritten sole copy, and Settings always reflects the committed mode rather than an in-flight requested value.

### S6 — Handle live synchronization, external edits, and conflicts

- Goal: make ongoing multi-device use safe after the switch has committed.
- Depends on: S5
- Refs: C1, C2, C6, C9, C10, C11, C13, C14 — no-loss behavior, frozen editor/URL lifecycle, fault scenarios, iOS 16 patterns, and Apple coordination/version contracts.
- Sub-steps:
  - S6.1 Route metadata/presenter events to debounced library revisions so active browser/tree/reference views refresh after remote add/move/rename/delete without polling loops.
  - S6.2 Present the open document through `NSFilePresenter`; update its URL after remote moves and reload remote content automatically only when the editor is clean.
  - S6.3 If a remote change arrives while the editor is dirty, preserve the remote bytes as a sibling conflict copy before atomically saving the active draft as the main document; notify the user without blocking editing.
  - S6.4 Resolve every distinct `NSFileVersion` conflict into a sibling copy, dedupe identical versions, then mark resolved and remove obsolete versions so they stop consuming iCloud quota.
  - S6.5 Handle remote deletion safely: clean documents close with an actionable message; dirty drafts are recovered as a new root-level Markdown document before the deleted screen closes.
  - S6.6 Preserve create/edit/rename/move/delete/import/share/AI-reference behavior during offline operation; queue normal iCloud uploads through the OS and never auto-fallback to local mode.
  - S6.7 Add deterministic presenter/version/offline/account-change tests and aggregate Settings-state tests without introducing persistent per-file status badges.
- Verify: simultaneous and external file operations preserve all distinct user content, settle conflicts, refresh live UI, and keep the storage mode invariant under offline/account failures.

### S7 — Full regression, multi-version QA, and release handoff

- Goal: prove compatibility and cloud behavior across builds, OS versions, devices, upgrades, and operational setup.
- Depends on: S6
- Refs: C1, C3, C7, C8, C9, C13, C14 — acceptance requirements, build/signing configuration, frozen regression entry points, S2 build evidence, and Apple runtime contract.
- Sub-steps:
  - S7.1 Run every existing test runner plus new compatibility/library/migration/cloud/conflict/i18n/privacy suites; keep frozen feature parity as a release blocker.
  - S7.2 Build Debug and Release for generic simulator and generic device at iOS 16.0, and run the unguarded-availability audit against the latest SDK.
  - S7.3 Test fresh install, upgrade with nested local data, empty library, large/deep library, interrupted enable/disable, low storage, quota error, account logout/change, and app termination at every migration checkpoint.
  - S7.4 Validate iOS 16 runtime behavior on a compatible physical device/runtime and current-iOS behavior on iPhone/iPad, including accessibility and system presentation fallbacks.
  - S7.5 On two signed physical devices using one account, verify create/edit/rename/move/delete/import/folders, offline edits, simultaneous edits, conflict copies, switch-off cloud retention, and safe re-enable merge.
  - S7.6 Verify Files app visibility, provisioning/entitlements in the archived product, privacy declarations, backup exclusions, README/AGENTS maintenance notes, and App Store capability readiness.
  - S7.7 Publish an iCloud troubleshooting/recovery runbook covering unavailable containers, stuck downloads/uploads, retained migration backups, conflicts, identity changes, and safe support diagnostics.
- Verify: all automated gates pass; real-device matrix passes; the archive contains correct iOS 16 minimum and iCloud entitlements; the runbook makes failures diagnosable without destructive reset advice.

## Milestones

- M1 — S1–S2: app is fully functional on iOS 16 in local-only mode.
- M2 — S3–S4: centralized library and signed cloud runtime are operational without user migration.
- M3 — S5: the switch and both migration directions are transactionally safe.
- M4 — S6–S7: ongoing multi-device synchronization is conflict-safe and release-verified.
