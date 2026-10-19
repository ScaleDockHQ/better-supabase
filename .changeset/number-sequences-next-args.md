---
"better-supabase": patch
---

`createNumberSequences().next()` sends `p_entity`, the name `next_number` declares, so the call reaches the function instead of failing to find it.
