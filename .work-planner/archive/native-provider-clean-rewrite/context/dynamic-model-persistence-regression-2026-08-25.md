# Refreshed model persistence regression — 2026-08-25

## User-observed behavior

- Opening Kimi settings initially shows three bundled models and does not show Kimi K3.
- Refreshing the model list returns K3 from the configured Kimi account.
- Selecting K3 and saving appears to succeed.
- Reopening settings restores `kimi-k2.6`; the refreshed list and selected K3 do not survive the settings lifecycle.

## Scope question

The user asked whether this is Kimi-specific or a shared Provider configuration defect. The investigation must distinguish:

1. a Provider-specific bundled-list freshness gap; and
2. shared settings initialization and refreshed-catalog persistence behavior.

