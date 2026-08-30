# Plan Summary — iOS 16 Compatibility and Optional iCloud Documents Sync

## Goal

Move Hashmark from an iOS 18+, local-Documents-only app to an iOS 16.0+ app that preserves every current feature and offers an explicit, lossless iCloud Documents switch. Local storage remains the default; users control when this device joins or leaves the synced library.

## Scope

- In: iOS 16 API compatibility, Xcode deployment settings, a centralized document-library service, iCloud Documents entitlements/container access, coordinated file I/O, metadata/download/conflict handling, transactional on/off migration, Settings status UI, seven-language copy, automated regression, and real-device verification.
- Out: CloudKit database records, document sharing/collaboration, version-history UI, automatic enablement, remote deletion on switch-off, per-file cloud badges, and syncing theme/language/AI configuration/API keys.

## Constraints / Coexistence

- Existing local users must see no automatic data movement after upgrade; the switch starts off until they explicitly enable it.
- Enabling, disabling, retrying, crashing, or changing iCloud accounts must never overwrite the only copy of a document or silently fork storage.
- iOS 16 keeps functional parity; newer-system-only visuals may use centralized system-appropriate fallbacks.
- All document access must distinguish an empty file from unavailable/not-downloaded/read failure; the current empty-string-on-error behavior cannot remain at the cloud boundary.
- UI copy follows the existing no-emoji, SF Symbols, Dynamic Type, accessibility, and seven-language i18n rules.

## Definition of Done

- Debug and Release compile with `IPHONEOS_DEPLOYMENT_TARGET=16.0`; the iOS 16 availability audit has no unguarded API failures and current iOS 26 behavior still builds.
- All existing AI, editor, browser, import, preview, sharing, settings, localization, and provider regression suites pass unchanged in capability.
- Toggle-on migrates a nested local fixture without loss, survives injected interruption, deduplicates identical cloud content, and preserves divergent content as conflict copies.
- Toggle-off downloads and verifies all cloud content before committing local mode and leaves the cloud library intact; re-enable performs the defined safe merge.
- Offline downloaded files remain editable, unavailable cloud-only files show retryable loading/error behavior, and an unavailable account never triggers silent local fallback.
- Two signed physical devices on the same iCloud account pass create/edit/rename/move/delete/import/folder, simultaneous-edit conflict, offline-edit, account-change, and on/off/re-enable tests.

## Context & References

| id | Source | Location | What it is for |
|---|---|---|---|
| C1 | Captured requirements and decisions | `context/ios16-icloud-requirements-2026-08-29.md` | Product semantics and safety invariants for every phase |
| C2 | Current file storage implementation | `MarkdownApp/MarkdownApp/Models/FileStore.swift` | Existing CRUD/import/Inbox behavior to preserve and refactor |
| C3 | Current project build configuration | `MarkdownApp/MarkdownApp.xcodeproj/project.pbxproj` | Deployment target, team, bundle ID, signing, and entitlements wiring |
| C4 | Current Observation usage | `MarkdownApp/MarkdownApp/Models/SettingsStore.swift`; `MarkdownApp/MarkdownApp/Features/AI/AIWritingSession.swift` | iOS 17 observation dependency to backport safely |
| C5 | Current Settings UI | `MarkdownApp/MarkdownApp/Features/Settings/SettingsView.swift` | Placement and interaction pattern for the iCloud switch/status |
| C6 | App shell and document lifecycle | `MarkdownApp/MarkdownApp/ContentView.swift`; `MarkdownApp/MarkdownApp/Features/Document/DocumentView.swift` | Library-root switching, navigation reset, dirty-document behavior |
| C7 | Current file regression tests | `MarkdownApp/FileBrowserTests/` | Local behavior baseline and migration test patterns |
| C8 | Apple ubiquity-container contract | https://developer.apple.com/documentation/foundation/filemanager/url%28forubiquitycontaineridentifier:%29 | Entitlements, background URL resolution, and unavailable-container behavior |
| C9 | Apple iCloud Documents design guide | https://developer.apple.com/library/archive/documentation/General/Conceptual/iCloudDesignGuide/Chapters/DesigningForDocumentsIniCloud.html | Coordinated iCloud document access requirements |
| C10 | Apple `NSFilePresenter` contract | https://developer.apple.com/documentation/foundation/nsfilepresenter | External change, move, deletion, and ubiquity notifications |
| C11 | Apple conflict-version contract | https://developer.apple.com/documentation/foundation/nsfileversion/isresolved | Preserve, resolve, and clean up conflict versions safely |
| C12 | Prior iCloud placeholder plan | `.work-planner/archive/ios-markdown-phase2-enhancements/plan.md` | Historical intent; superseded by this detailed plan |
| C13 | S1 freeze and impact report | `context/s1-freeze-and-impact-report-2026-08-29.md` | Executable behavior baseline, complete iOS 16/FileStore/URL inventory, and fault-injection contract |
| C14 | S2 iOS 16 completion report | `context/s2-ios16-backport-report-2026-08-29.md` | Implemented observation/UI compatibility architecture plus iOS 16 build, simulator launch, form-factor, and preview evidence |

## Assumptions and External Preconditions

| Item | Status | Why it matters | Resolution point |
|---|---|---|---|
| iCloud container is `iCloud.com.kvsur.MarkdownApp` | verified | Entitlements, signed runtime, Files visibility, and final user acceptance use the same container | Completed in S4 and accepted in S7 |
| Documents/folders are the only synced data | assumed | Avoids leaking API keys and keeps device preferences independent | Locked unless the user explicitly expands scope before S5 |
| Apple Developer team can register the container | verified | Signed iCloud testing and Files visibility passed | Completed in S4; final archive readiness accepted in S7 |
| iOS 16 runtime/device is available for acceptance | verified | iOS 16.0 iPhone/iPad runtime smoke, compatibility UI, and final user acceptance passed | C14 and S7 contain the evidence |

## Key Decisions (locked)

| Decision | Choice | Why |
|---|---|---|
| Minimum version | iOS 16.0 | Matches the requested support floor |
| Observation compatibility | Combine `ObservableObject` family | Native iOS 16 support without adding a backport dependency |
| Cloud technology | iCloud Documents ubiquity container | Fits the existing real-file hierarchy and Files app integration |
| Enable behavior | Explicit Settings confirmation and transactional local-to-cloud migration | No surprise migration and no partial mode switch |
| Disable behavior | Download/verify local copy, switch locally, retain cloud data | Never deletes other devices' data |
| Re-enable merge | Hash-identical dedupe; divergent items preserved under conflict-copy names | No last-writer-wins data loss |
| Unavailable account | Stay in cloud mode, expose retry/disable actions | Prevents silent local/cloud forks |
| Status UI | Aggregate status in Settings only | Matches the requested UI scope while preserving actionable errors |
