---
"better-supabase": patch
---

A `P0002` error (`no_data_found`, raised by `select ... into strict` or `raise exception using errcode = 'no_data_found'`) now maps to the `not_found` kind with status 404 instead of `unexpected`. The `code` field still says `P0002`, so you can tell it from `PGRST116`.
