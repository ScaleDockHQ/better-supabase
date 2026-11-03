---
"better-supabase": minor
---

The `streams` module stores chunks as `bytea` (module version 2, with an upgrade that converts existing text chunks). `StreamStore.append` accepts `string` or `Uint8Array` chunks, the Postgres store adds `readBytes`, and `resumableStreamContext(store)` from `better-supabase/streams` answers the `resumable-stream` context API, so the AI SDK resume route works on Postgres. The `queue` module moves a waiting message earlier when a repeated dedupe key arrives with a shorter delay.
