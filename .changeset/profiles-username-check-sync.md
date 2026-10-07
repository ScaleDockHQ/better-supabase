---
"better-supabase": patch
---

The profiles module's username check compares the length with `>=` and `<=` instead of `between`. Postgres stores a `between` inside an `and` chain with a different nesting than the expression pg-delta writes back, so `supabase db schema declarative sync` dropped and re-added `profiles_username_check` on every run. Run `better-supabase sql sync` and generate a migration to pick it up.
