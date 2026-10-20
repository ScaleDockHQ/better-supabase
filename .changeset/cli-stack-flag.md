---
"better-supabase": minor
---

`seed --apply` and `db query` accept `--stack <name>` (or `$BSB_STACK`) to connect to the stack in `supabase/stacks/<name>/config.toml` instead of the default local stack.
