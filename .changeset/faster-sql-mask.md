---
"better-supabase": patch
---

Rendering blocks and running `doctor` or `upgrade` are faster again. The SQL scanner that finds policies and grants now copies untouched text in whole slices, so the actor guard's policy read no longer slows every render.
