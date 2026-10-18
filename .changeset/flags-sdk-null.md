---
"better-supabase": patch
---

The Flags SDK adapter serves a `null` variant when the declaration's `defaultValue` is `null` or left out, and treats a default variant that is missing from the variants as a missing flag instead of `null`. `evaluateFlag` returns `found`, so callers can tell the two apart. A flag row with an unknown `type` always serves its fallback: the OpenFeature provider resolves it with `PARSE_ERROR` (or `GENERAL` when the `errorCodes` map has none), and `getProviderData` shows it as a hint in Flags Explorer.
