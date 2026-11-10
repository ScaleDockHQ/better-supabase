---
"better-supabase": patch
---

A cursor page that asks for a count (`withCount`) reads its rows and its count at the same time instead of one after the other, so a later page costs one round trip of latency, not two.
