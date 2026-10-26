---
"better-supabase": minor
---

`better-supabase init` adds the `rls-guard` block to the config it writes, so row level security stays on for every table the project creates later. Remove `'rls-guard'` from `blocks` to opt out (ADR 0104).
