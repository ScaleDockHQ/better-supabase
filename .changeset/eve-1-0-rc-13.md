---
"better-supabase": minor
---

`better-supabase/eve` follows eve 1.0.0-rc.13, which bundles Workflow 5.5:
the `eve` peer range is now `>=1.0.0-rc.13 <2` and `@vercel/connect` starts
at 2.7.0. `persistSessions` stores a `content.completed` part without a
`runId`, which eve now sends for a part its turn wrote without a model run.
`queueDynamicSchedules` keys `collections` by the collection name, which is
the definition's new `id` when it sets one.
