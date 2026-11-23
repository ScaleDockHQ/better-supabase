---
"better-supabase": patch
---

`claim_next_task` picks another ready task when a racing worker committed its claim on the first one, instead of raising `TASK_CLAIMED`.
