---
"better-supabase": minor
---

The Workflow SDK integration follows `workflow` 5.2 (breaking for graph approvals). An approval node always files an approvals request through the runtime's `requestApproval`, which is now required, and `graphStarter` refuses a live run of a graph with an approval node unless you pass `approval`. `approvalToken` is removed, because a token derived from the run key could be guessed; resume the node with `wakeOnApproval`. The Supabase World speaks protocol 5.0.4, reads `WORKFLOW_POSTGRES_MAX_POOL_SIZE` (with `WORKFLOW_POSTGRES_MAX_CONNECTIONS` as an alias), and adds `registerRoute` and `registerHandler` so a queue prefix can go to its own route or run in-process. `approvalWaiter` and the durable chat resume use the SDK's `HookNotFoundError`, and `durableTurn` takes an optional `setAttributes` that records the turn's `bsb.phase`.

| 0.31                          | 0.32                                                  |
| ----------------------------- | ----------------------------------------------------- |
| `approvalToken(runKey, node)` | the approvals request id `requestApproval` returns    |
| `graphStarter({ ... })`       | `graphStarter({ ..., approval })` for approval graphs |
