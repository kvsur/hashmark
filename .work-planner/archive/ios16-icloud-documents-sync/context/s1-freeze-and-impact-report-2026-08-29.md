# S1 Behavior Freeze and Compatibility/Storage Impact Report

Captured on 2026-08-29 for baseline commit `ecf1aa7` on branch `work-icloud-sync-supported`.

## 1. Environment and baseline

- Xcode: 26.6 (`17F113`).
- Installed simulator runtime: iOS 26.5 only.
- Project deployment target at capture: iOS 18.0 in Debug and Release.
- Bundle identifier: `com.kvsur.MarkdownApp`.
- The worktree already contained the new `.work-planner/` plan/archive changes. Production Swift was unchanged when the initial baseline was run.
- iOS 16 runtime behavior cannot be executed on this machine. Compile auditing uses the iOS 26.5 SDK with `IPHONEOS_DEPLOYMENT_TARGET=16.0`; real iOS 16 acceptance remains an external S7 gate.

### Initial committed-code baseline

| Command/suite | Result |
|---|---|
| `zsh MarkdownApp/AIReasoningTests/run-all.sh` | PASS; 16 constituent suites completed |
| `FileStoreRegressionTests` | PASS |
| `DocumentActivityResolverTests` | PASS |
| `MarkdownEditingEngineTests` | PASS |
| Debug, generic iOS Simulator, unsigned | BUILD SUCCEEDED |
| Release, generic iOS Simulator, unsigned | BUILD SUCCEEDED |
| Debug, generic iOS device, unsigned | BUILD SUCCEEDED |
| Release, generic iOS device, unsigned | BUILD SUCCEEDED |

`capture-live-model-snapshot.sh` is a credentialed maintenance capture, not a deterministic test suite. `run-model-drift-audit.sh` is a two-input CLI exercised by `run-model-drift-tests.sh`; both are therefore represented by the aggregate suite without making network calls or inventing live inputs.

## 2. Frozen local behavior

The executable S1 regression entry point is:

```sh
zsh MarkdownApp/DocumentLibraryTests/run-step1-tests.sh
```

It freezes the following behavior:

- File creation, sanitized names, unique-name suffixes, read/write, rename, move, recursive delete, tree generation, and recursive activity ordering.
- Folders sort before documents; each group sorts by effective modification date and then stable natural name.
- External imports preserve source bytes; extensionless imports receive `.md`.
- `Documents/Inbox` stays hidden and is not a real library location; a successful Inbox import removes its staging source; purge removes abandoned staged items.
- Store containment resolves symlinks, rejects Inbox, and rejects path-prefix siblings.
- A document loads once; a clean draft does not write; switching saves the dirty old URL before reading the new URL; selecting the same URL is a no-op.
- An external-open URL is read exactly once, retains source identity, derives its title by removing the extension, accepts a readable empty file, and rejects an unreadable file.
- AI document references flatten nested trees in tree order, filter by selected URL, skip empty/unreadable content, trim surrounding whitespace, and retain URL identity for deduplication.

The UI now delegates these three previously private behaviors to focused models without changing visible behavior:

- `Models/DocumentDraft.swift`
- `Models/ImportedDocument.swift`
- `Models/DocumentReferenceResolver.swift`

## 3. iOS 16 availability inventory

An unsigned Debug simulator build with a command-line-only `IPHONEOS_DEPLOYMENT_TARGET=16.0` override fails with exit 65. The first compiler barrier is Observation, as expected; the project file itself remains at iOS 18 until S2.6.

Local SwiftUI SDK interfaces confirm:

- two/zero-argument `onChange` and its `initial` parameter require iOS 17;
- `ContentUnavailableView` requires iOS 17;
- `defaultScrollAnchor` requires iOS 17;
- `presentationDetents` and `presentationDragIndicator` support iOS 16.0;
- `presentationContentInteraction` and `presentationCompactAdaptation` require iOS 16.4;
- `topBarLeading` and `topBarTrailing` are back-deployed to iOS 14 and are not blockers.

### Observation ownership and injection

| Surface | Current dependency | S2 action |
|---|---|---|
| `Models/SettingsStore.swift` | `@Observable` | `ObservableObject` + `@Published` |
| `MarkdownAppApp.swift` | `@State` ownership and `.environment(settings)` | `@StateObject` + `.environmentObject` |
| `ContentView.swift` | typed `@Environment(SettingsStore.self)` | `@EnvironmentObject` |
| `DesignSystem/LanguageRebuild.swift` | typed `@Environment(SettingsStore.self)` | `@EnvironmentObject` |
| `Features/Settings/SettingsView.swift` | typed environment plus local `@Bindable` | environment object plus explicit bindings |
| `Features/Settings/LanguagePickerSheet.swift` | typed environment | `@EnvironmentObject` |
| `Features/AI/AIWritingSession.swift` | `@Observable`, `@ObservationIgnored` | `ObservableObject`, focused `@Published`, ordinary ignored storage |
| `Features/AI/AIWritingGenerationView.swift` | `@Bindable AIWritingSession` | `@ObservedObject` |
| `Features/AI/AIWritingView.swift` | reassignable `@State` session | stable `@StateObject` with idle-only reconfiguration |

### Every two-argument/initial `onChange` site (16 total)

| File | Values/behavior that must be preserved |
|---|---|
| `ContentView.swift` | incoming preview closes → purge Inbox; initial and later theme application |
| `Features/Document/DocumentView.swift` | mode change → save/configure scroll; size-class change → configure scroll |
| `Features/Settings/AIConfigEditorView.swift` | provider old/new transition; base URL catalog reload; model metadata sync |
| `Features/Browser/FileBrowserView.swift` | reload token refresh |
| `Features/AI/AIWritingView.swift` | dynamic type, vertical size class, phase old/new transition, answer start, background interruption |
| `Features/AI/AIAttachmentBar.swift` | photo item ingestion |
| `Features/AI/AIConfigGate.swift` | trigger consumption |
| `Features/AI/AIWritingPromptView.swift` | prompt focus expansion |

The AI phase transition is the only site that requires the old value for behavior. S2 must explicitly retain previous phase. Theme application also requires an explicit initial `onAppear` path on iOS 16.

### Empty state, scrolling, and presentation

| Category | Sites | Compatibility requirement |
|---|---|---|
| `ContentUnavailableView` | Browser, switcher, outline, document-reference picker, AI error state (5) | one reusable iOS 16 fallback preserving label, description, actions, Dynamic Type, and accessibility |
| `defaultScrollAnchor(.bottom)` | `AIReasoningTraceView.swift` (1) | bottom-follow behavior compatible with iOS 16 |
| `presentationDetents` | Name input, AI writing, About, reference picker, document switcher, outline (6 modifiers) | already iOS 16.0; preserve detents |
| `presentationDragIndicator` | AI writing and document switcher (2) | already iOS 16.0 |
| `presentationContentInteraction` | AI writing (1) | central iOS 16.4 guard with 16.0–16.3 default behavior |
| `presentationCompactAdaptation` | document AI popover (1) | central iOS 16.4 guard with 16.0–16.3 default behavior |
| Liquid Glass/new toolbar composition | `GlassBackground.swift`, `DocumentView.swift` | existing iOS 26 guards remain centralized/documented; fallback must cover iOS 16–25 |

## 4. FileStore construction and active-root map

There are exactly two direct runtime `FileStore()` constructions:

| Construction | Consumers | Required S3 ownership change |
|---|---|---|
| `ContentView.swift` | browser root, navigation destinations, external-open preview/import, Inbox purge | replace with the root-owned injected document library/controller |
| `Features/AI/AIWritingView.swift` | prompt attachment bar → document-reference picker/tree/read | inject the same active library used by the browser; never rediscover local Documents |

`FileStoreRegressionTests.swift` also constructs `FileStore(fileManager:rootURL:)`; that is a test fixture and must remain injectable.

All existing UI store dependencies flow from those runtime roots:

- Browser: `FileBrowserView`, `DirectoryPicker`, `ImportPreviewButton`, `ImportTargetPicker`.
- Document: `DocumentView`, `DocumentSwitcherSheet`, preview/source sharing.
- Import/external-open: `ReadOnlyPreviewView` plus Inbox cleanup in `ContentView`.
- AI: `AIWritingPromptView` → `AIAttachmentBar` → `DocumentReferencePicker`.

## 5. URL identity assumptions

| Identity use | Current assumption | Required mode/root behavior |
|---|---|---|
| `DocumentNode.id` and `DocumentTreeNode.id` | absolute URL is SwiftUI identity and navigation hash | changing active root changes every identity; reset navigation/sheets atomically |
| `ContentView.path: [DocumentNode]` | path nodes remain valid under the current root | clear path before/with committed mode change |
| `DocumentDraft` / `DocumentView` | raw URL equality selects current document; save uses current node URL | save/resolve dirty document before root switch; never write an old-root URL afterward |
| `DocumentSwitcherSheet.currentURL` | raw URL highlights current item | tree and current URL must come from the same library revision/root |
| `DirectoryPicker.stack: [URL]` | root and descendants stay valid for sheet lifetime | dismiss/reset picker on mode identity change |
| Browser move validation | standardized path equality/prefix prevents same-parent no-op and folder cycles | validate against the active coordinated root and canonical relative paths |
| `FileStore.isInsideStore` | resolved absolute paths distinguish root, Inbox, external items, and escaping symlinks | accept explicit active root and separate fixed local Inbox root |
| AI selected/referenced URLs | `Set<URL>` deduplicates and preselects references | clear/rebase references when active root identity changes; resolve content through service |
| external/source URLs | source URL is retained for import/share | keep external security-scoped identity separate from library-relative identity |
| conflict/re-enable merge | no current relative identity type | introduce normalized relative paths for migration, merge, and cross-root comparison |

## 6. Fault-injection seams and executable scenarios

`DocumentLibraryFaultInjectionTests.swift` defines nine stable checkpoints and verifies that each fails exactly once, preserves its identity, and can be retried. Each checkpoint has a no-data-loss invariant.

| Checkpoint | Production seam to inject | Required invariant |
|---|---|---|
| `containerResolution` | async ubiquity-container resolver | keep committed mode; expose retry; no local fallback fork |
| `download` | ubiquitous item download/request waiter | retain sole cloud copy; do not commit local mode |
| `copy` | coordinated copier | retain source bytes and resume from journal |
| `write` | atomic writer | previous destination remains intact |
| `delete` | coordinated cleanup | cleanup debt may remain; no other sole copy is deleted |
| `crashBeforeModeCommit` | migration journal checkpoint before preference commit | resume or roll back under old mode |
| `crashAfterModeCommit` | checkpoint immediately after preference commit | launch under new mode and finish idempotent cleanup |
| `externalChange` | file-presenter/metadata event source | refresh clean consumers; preserve dirty drafts |
| `versionConflict` | `NSFileVersion` provider/resolver | materialize every distinct byte sequence before resolution |

Later implementations must expose these as injected protocols/closures or fakes rather than relying on filesystem permissions or timing. The test enum is the canonical scenario vocabulary; S4–S6 tests should drive their real services through the same names.

## 7. S1 completion gate

S1 is complete when all of the following remain true after the behavior extractions:

1. `run-step1-tests.sh` passes all four document suites.
2. The full existing AI and Markdown editing suites pass.
3. Debug/Release simulator and unsigned device builds pass at the committed iOS 18 baseline.
4. The iOS 16 override build fails only on inventoried compatibility work until S2 removes each item.
5. Direct `FileStore()` construction and URL identity lists have no unclassified runtime entry point.
6. Every required fault category has an executable checkpoint and stated invariant.
