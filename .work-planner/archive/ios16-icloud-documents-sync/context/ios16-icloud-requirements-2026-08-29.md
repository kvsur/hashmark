# iOS 16 + iCloud Requirements Capture

Captured on 2026-08-29 from the planning conversation.

## Verbatim user requirements

> 当前app的最低版本兼容是iOS18，在不改动现有功能的情况下，能降级支持到iOS16及以上么？

> xcode配置是不是也需要更新呢？

> iCloud需要有开关，明确好开/关 切换逻辑

> ok，创建新的任务planer

## Confirmed choices

- The plan covers both iOS 16 compatibility and iCloud document synchronization.
- iCloud synchronization is opt-in through a Settings switch; existing installs remain local until the user enables it.
- Enabling iCloud safely migrates all local Markdown documents and folders while preserving hierarchy.
- Disabling iCloud first downloads and verifies a complete local copy, switches this device to local storage, and never deletes the cloud copy.
- Re-enabling iCloud merges safely: identical files are deduplicated and divergent same-path files are both preserved.
- If the iCloud account or container becomes unavailable, the app remains in iCloud mode and reports the problem instead of silently creating a local fork.
- Sync/account/migration status is shown in Settings only; the browser does not add persistent per-file cloud badges.

## Safety defaults adopted for the unanswered details

- Only Markdown documents and their folder hierarchy sync. Theme, language, AI profiles, API keys, caches, and other app settings remain device-local.
- The exact deployment target is iOS 16.0.
- iCloud Documents/ubiquity storage is used rather than a CloudKit database, preserving the existing file/folder model and Files app interoperability.
- The intended container identifier is `iCloud.com.kvsur.MarkdownApp`, matching the current `com.kvsur.MarkdownApp` bundle identifier.
- Cloud data is never destructively removed as a side effect of turning the switch off.
