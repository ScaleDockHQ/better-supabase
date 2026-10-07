---
"better-supabase": patch
---

The `notifications` module derives the event id of a keyed send without a key column (`columns.events.key: null`) as a UUIDv8 (RFC 9562) from the MD5 of the tenant and the key, in place of the plain MD5 cast to `uuid`, which strict validators such as `z.uuid()` reject. The id stays deterministic per tenant and key. Events stored before keep their MD5 ids, and a keyed send that matches one still returns that id instead of notifying twice.
