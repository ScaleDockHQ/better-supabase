---
"better-supabase": patch
---

The request stats record a miss for `bsb.cached()` and `bsb.public()` entries when their body runs, with the new entry kinds `private` and `public`.
