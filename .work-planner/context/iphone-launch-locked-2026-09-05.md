# Physical iPhone launch blocked by lock screen

Captured: 2026-09-05 21:33:08

## Verified

- `kvsur的iPhone` (iOS 27.0) is an available Xcode destination.
- Debug device build and code signing succeeded.
- The development build installed successfully as `com.kvsur.MarkdownApp`.

## Launch result

The Debug iCloud smoke launch was denied before the app process started:

```text
Unable to launch com.kvsur.MarkdownApp because the device was not, or could not be, unlocked.
```

## Unblock condition

Unlock the connected iPhone and keep its screen awake, then rerun the existing
`--hashmark-icloud-smoke document-title-20260905-phone` launch.
