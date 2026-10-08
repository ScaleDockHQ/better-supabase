---
"better-supabase": minor
---

API keys report whether they still authenticate. Every key that `create`, `list`, `rotate` and `verify` return has `state` (`active`, `grace`, `revoked` or `expired`), computed with the database `now()`, so a list shows a rotated key as still working while its grace period runs instead of as revoked. A rotated key also has `successorId`, the key that replaced it. The SQL functions add `state` and `successor_id` to each key object, and `ApiKeyState` is exported.
