---
"better-supabase": patch
---

`canonicalJson` skips the key sort for objects whose keys are already in order, and `snapshotOf` returns the snapshot it already built for the same verified auth state.
