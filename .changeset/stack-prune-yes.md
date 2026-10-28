---
"better-supabase": patch
---

`dev stack prune` passes `--yes` to `supabase stack destroy` once it has the user's consent, so the destroy no longer fails with `ExperimentalStackDestroyError`. A `--confirm` token now ignores the presentation flags `--yes`, `--json`, `--color`, `--debug` and `--agent`, so adding one of them to the run the user agreed to keeps the token valid.
