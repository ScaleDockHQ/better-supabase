---
"better-supabase": minor
---

`subjects.can`, `subjects.view` and `subjects.record(subject)` check a batch of actions through `can_subject` and read a record's header with them in one call. The `subjects` module now exposes `can_subject` to members.
