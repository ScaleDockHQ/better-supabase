---
"better-supabase": minor
---

`bsb.action` takes `evictSession`. After a successful call the library drops every cached entry of the caller, as `bsb.evictSession(userId)` does.

| Before                                             | After                |
| -------------------------------------------------- | -------------------- |
| `await bsb.evictSession(auth.user.id)` in the body | `evictSession: true` |
