# S2 iOS 16 Backport Completion Report

Completed on 2026-08-29 with Xcode 26.6 and the iOS 26.5 SDK.

## Result

- Debug and Release resolve `IPHONEOS_DEPLOYMENT_TARGET = 16.0` for both `iphoneos` and `iphonesimulator`.
- The latest installed Base SDK remains iOS 26.5.
- The complete local-only app compiles for generic iOS Simulator and unsigned generic iOS device in Debug and Release.
- No production feature file contains Observation macros, typed Observation environment injection, two-argument/initial `onChange`, or `defaultScrollAnchor`.
- Newer APIs remain available through centralized guarded components; iOS 16 behavior is the default fallback.

## Compatibility architecture

| Concern | iOS 16-compatible implementation |
|---|---|
| Settings observation | `ObservableObject`, `@Published`, root `@StateObject`, and `@EnvironmentObject` |
| AI session observation | stable `@StateObject`, focused `@Published` UI state, `@ObservedObject` presentation |
| AI configuration refresh | `AIWritingSession.reconfigure` accepts changes only while idle and preserves object identity |
| Change callbacks | iOS 16 one-value `onChange`; explicit prior AI phase/provider state; theme initial application in `onAppear` |
| Empty/error states | `AppEmptyStateView`: native iOS 17+ `ContentUnavailableView`, equivalent iOS 16 fallback |
| Reasoning scroll | `BottomFollowingScrollView` using `ScrollViewReader` on iOS 16+ |
| iOS 16.4 presentations | `CompatiblePresentation` applies content/popover adaptation only when available |
| iOS 26 toolbar | `DocumentBottomToolbar` owns the guarded `ToolbarSpacer` layout |
| Liquid Glass | `GlassBackground` uses native iOS 26 glass and iOS 16–25 material fallback |

## Verification

All commands completed with exit 0:

- `zsh MarkdownApp/AIReasoningTests/run-all.sh`
- `zsh MarkdownApp/DocumentLibraryTests/run-step1-tests.sh`
- `MarkdownEditingEngineTests`
- Debug generic iOS Simulator build
- Debug unsigned generic iOS device build
- Release generic iOS Simulator build
- Release unsigned generic iOS device build

The AI aggregate includes the new idle-only session reconfiguration assertions. Static auditing found newer availability references only inside `AppEmptyStateView`, `CompatiblePresentation`, `GlassBackground`, and `DocumentBottomToolbar`, each protected by its corresponding availability check.

## iOS 16 runtime validation

After the iOS 16.0 (20A360) simulator runtime became available locally, the backport was exercised on both form factors with Xcode 26.6:

- iPhone 14 Pro, iOS 16.0
- iPad Air (5th generation), iOS 16.0

Debug and Release builds both succeeded against the concrete iPhone destination with an `arm64-apple-ios16.0-simulator` target. Both products installed and launched on the iPhone and iPad, remained registered as live UIKit processes, and produced no MarkdownApp crash report.

Runtime smoke evidence:

- The root browser rendered its iOS 16 empty-state fallback correctly on both devices.
- An external Markdown URL entered the existing `onOpenURL` flow and rendered the bundled third-party notice in the read-only Web preview.
- A temporary Markdown document in the local Documents root loaded in `DocumentView`; the Preview/Edit segmented control, share action, bottom toolbar fallback, and complete offline Web preview rendered on iOS 16.
- The exact temporary simulator document was removed after validation.

Each MarkdownApp launch emitted one non-fatal `libxpc` assertion in the iOS 16 simulator log. The same assertion reproduced when launching Apple's Settings app in that runtime, while MarkdownApp remained alive and generated no crash report, so this is recorded as an Xcode 26.6/CoreSimulator-old-runtime artifact rather than an application regression.

## Remaining S7 acceptance scope

The local runtime smoke removes the simulator-availability gap, but it does not replace S7 manual and physical-device acceptance. Desktop accessibility control was unavailable (`osascript` was denied assistive access), so automated taps through edit/save, Settings, AI sheets, import confirmation, and full CRUD were not claimed. Those flows remain covered by the frozen model/regression suites and must receive UI/manual coverage during S7, together with physical-device and current-iOS checks.
