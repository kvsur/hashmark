# S5 Owner Smoke internal group verification

Date: 2026-08-31

## Result

- Created the internal TestFlight group `Owner Smoke`.
- Enabled automatic distribution for Xcode-uploaded builds. This group is reserved for the Account Holder's pre-release smoke tests.
- TestFlight automatically added iOS `1.0 (1)` to the group.
- Added the existing Account Holder as the sole internal tester; App Store Connect shows tester status `已邀请`.
- Verified group summary: 1 internal tester and 1 build.

## Operational note

For future Xcode uploads, `Owner Smoke` should receive the processed build automatically. Keep this group limited to the author; add friends only through the separate external `Friends Beta` group after owner smoke testing passes.

## Next action

Accept the invitation on the Account Holder's iPhone, install `Hashmark 1.0 (1)` through TestFlight, and execute the S5 device smoke checklist.
