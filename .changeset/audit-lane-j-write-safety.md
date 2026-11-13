---
"better-supabase": minor
---

Updates can refuse a stale write, creates can be retried safely, and block controllers can write optimistically. A change in `tasks.update` and `deals.update` takes `expectedVersion` (the row's `updatedAt` as you read it) and is refused with a `conflict` error, hint `STALE_WRITE`, when the row changed since. `tasks.create`, `deals.create` and `quotes.create` take `idempotencyKey` when their creator gets `idempotency: createIdempotency(...)`. `createBlockMutation` and the `useBlockMutation` hooks take `optimistic`, built with `optimisticUpdate`, `optimisticArchive` or `optimisticReorder`. `better-supabase` exports `isStaleWrite`, `STALE_WRITE` and `staleWriteError`, and `EntitySurface` gains `expectedVersion` and `idempotent`. Re-run `better-supabase upgrade` to install the changed `update_tasks` and `update_deals` functions; their signatures do not change.

| Before                                                    | After                                                                                            |
| --------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `update({ changes: [{ taskId, field, value }] })`         | `update({ changes: [{ taskId, field, value, expectedVersion: task.updatedAt }] })`               |
| `create({ organizationId, input })` ran again on retry    | `create({ organizationId, input, idempotencyKey })` returns the first result                     |
| `useBlockMutation(tasks, "update", { engine, instance })` | `useBlockMutation(tasks, "update", { engine, instance, optimistic: optimisticUpdate({ ... }) })` |
