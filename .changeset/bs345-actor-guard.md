---
"better-supabase": patch
---

Doctor's BS345 check treats the `actor_may_write()` support-session guard as tenant membership, so app tables that carry the guard no longer raise a false warning for attachment subjects.
