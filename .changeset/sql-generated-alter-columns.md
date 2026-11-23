---
"better-supabase": patch
---

Fix the `alter table ... add column if not exists` statements the blocks write over an app's own table. A column default such as `array['a', 'b']` is no longer cut at its comma, and a `not null` inside a `check (...)` is no longer removed, so the generated SQL parses. The `moderation` and `waitlist` modules change when an app owns their tables.
