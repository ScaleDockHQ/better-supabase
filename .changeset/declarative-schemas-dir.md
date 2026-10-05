---
"better-supabase": patch
---

Fix the build after #30 and #34: the declarative schemas folder for `supabase db diff` now resolves next to the `supabase/config.toml` the CLI found, so it also works from a package inside a workspace.
