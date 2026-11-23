---
"better-supabase": patch
---

`better-supabase/next` loads the block clients that `bsb.record()` and `bsb.recordAt()` call on their first call instead of at import. A fresh Node process evaluates the entry in 93.1 ms instead of 104.5 ms, and loads 89 files (224.2 KB gzip) instead of 109 (256.8 KB).
