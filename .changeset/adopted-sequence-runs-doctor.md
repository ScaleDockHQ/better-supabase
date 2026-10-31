---
"better-supabase": patch
---

Doctor rule BS425 reports a `members` table adopted for sequence runs in `blocks.sequences.tables`, which the 0.47 upgrade does not move, and `codemod 0.47` lists the key for review. The migration guide states that event subscriptions can't filter on a program.
