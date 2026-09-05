# Document title flow iCloud smoke block

Captured: 2026-09-05 21:23:16

## Environment

- Device: iPhone 17 Pro simulator, iOS 26.5
- App: Debug simulator build
- Runner: `ICloudDeviceSmokeRunner`
- Token: `document-title-20260905`

## Result

The runner returned `success: false` before creating any cloud fixture:

```text
The real iCloud runtime is not ready: cloudUnavailable(reason: "iCloud Drive is unavailable for this account or device.")
```

The simulator preference was restored to local mode after the attempt. The local
create → write → rename → continue editing → reconstruct controller → reopen loop
passed in `DocumentLibraryServiceTests.testLocalCreateRenameContinueAndReopen`.

## Unblock condition

Run the existing Debug smoke runner on a simulator or physical device signed into
an account with iCloud Drive enabled, then complete the tokened external edit that
the runner waits for.
