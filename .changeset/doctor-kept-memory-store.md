---
"better-supabase": patch
---

Doctor warns (BS647) when the app calls `bsb.kept()` and sets no `kept.store` in `createNext`, or sets `memoryKeptStore()`, because each instance then keeps its own copy of every entry.
