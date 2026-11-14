---
"better-supabase": minor
---

Rename two types of the bulk call to names that follow the naming vocabulary. `BulkOptions` was the retired name of `BulkActionsOptions`, and `Failure` is a banned type suffix. Both types shipped in the same unreleased version as `bulk`, so no released code changes. `BULK_TOO_MANY` is now a shared hint code, because `bulk-actions`, `organizations` and `tasks` raise it.

| Old           | New               |
| ------------- | ----------------- |
| `BulkOptions` | `BulkCallOptions` |
| `BulkFailure` | `BulkItemError`   |
