---
"better-supabase": minor
---

`doctor`, `gen`, `db query` and `seed --apply` no longer guess port 54322 for the local stack. When `supabase/config.toml` sets no `[db] port` and `supabase status` fails, they stop with `not_found` and name both sources, so a per-worktree stack (`supabase start --runtime native`) can't reach another project's database on 54322. `--stack <name>` (or `$BSB_STACK`) reads `supabase status --stack <name>` when `supabase/stacks/<name>/config.toml` sets no port.
