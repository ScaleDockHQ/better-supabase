---
"better-supabase": minor
---

`defineSupabase(schema, { diagnostics: true })` writes a debug record to `logger` for every query, database error, session refresh and auth resolution: the table, operation, outcome, timing and row count. The records never contain tokens, user ids, row values, filters or database error messages, and a throwing logger never changes a result. It follows the Supabase SDK diagnostic logging capability, pinned as `SPEC_PINS.supabaseSdkCapabilities` (capability matrix 1.14.0). The option is off by default.
