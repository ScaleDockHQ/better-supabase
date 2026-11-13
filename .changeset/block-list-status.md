---
"better-supabase": minor
---

Block reads have one list status and a realtime refetch. `blockListStatus(state)` maps a `useBlockQuery` state to `BlockListStatus` (`loading`, `empty`, `error` or `ready`), and `blockRealtimeRefetch(block, entity, source)` returns the `refetchOn` of an entity that declares `realtime: true`. Both are exported from `better-supabase/react`, `/vue`, `/svelte` and `/solid`.

| Before                                           | After                                                         |
| ------------------------------------------------ | ------------------------------------------------------------- |
| `if (list.status === "loading") ...` per list    | `blockListStatus(list).kind`                                  |
| `refetchOn: { source, types: ["task.created"] }` | `refetchOn: blockRealtimeRefetch(tasksBlock, "task", source)` |
