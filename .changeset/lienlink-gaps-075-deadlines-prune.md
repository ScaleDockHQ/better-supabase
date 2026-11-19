---
"better-supabase": minor
---

`prune_deadlines` with `pending_only => false` (`deadlines.forget`) deletes satisfied history, so it now also checks the new `prune` action of `blocks.deadlines.permissions`. It defaults to the key `manage` maps to (`deadlines.manage`); set `permissions.prune` to a key fewer roles hold to keep it narrower. Pruning pending deadlines, alone or with `computeMany({ prune: true })`, still needs only `deadlines.write`. A caller without the key gets `DEADLINE_FORBIDDEN`.
