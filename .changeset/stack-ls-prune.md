---
"better-supabase": minor
---

Add `better-supabase stack ls` and `stack prune` for the Supabase CLI's managed stacks.

- `stack ls` lists every stack with its branch, project root and running state, marks stacks whose worktree or branch is gone, and counts the System V shared memory segments each one holds against the system limit.
- `stack prune` destroys the stacks whose worktree or branch is gone, never the one for this checkout. `--stop-idle` also stops the running stacks of other branches, and `--dry-run` prints the plan. Destroying a stack needs consent in agent mode.
- The command manifest has a new effect kind, `stacks`, with `read` or `write` access, in `schemas/cli-commands-v1.json`.
