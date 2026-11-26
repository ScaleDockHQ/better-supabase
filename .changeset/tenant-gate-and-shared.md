---
"better-supabase": minor
---

Add `gate: true` to the options of `bsb.tenant()`, `bsb.activeTenant()` and `bsb.auth()`, and add `bsb.shared(ref, permission, read)`. A gated scope returns before the permission check settles and its `db` settles each read after it, so a cold call costs one round trip. `bsb.shared` checks the caller outside the cache, then returns a `"use cache"` read shared by every member of the tenant.

| Before                             | After                                              |
| ---------------------------------- | -------------------------------------------------- |
| scope returned after the check     | `bsb.tenant(ref, permission, { gate: true })`      |
| a tenant read cached once per user | `bsb.shared(ref, permission, (t) => readOf(t.id))` |
