---
"better-supabase": minor
---

Streams work with the `resumable-stream` package and the AI SDK's `consumeSseStream`. The `streams` SQL module moves from version 2 to 3, so run `better-supabase upgrade`.

- `resumableStreamContext` now matches `resumable-stream`: `resumeExistingStream` resolves `undefined` for a stream that was never created and `null` for one that finished (it replayed the whole text before; pass `replayFinished: true` to keep that), and a new `resumableStream(id, make, skip)` creates the stream or joins the running one.
- New `consumeSseStreamInto(store, { streamId, onStreamId, waitUntil })` for `toUIMessageStreamResponse({ consumeSseStream })`.
- New `better-supabase/streams/resumable` with `postgresPublisher` and `postgresSubscriber`, so `createResumableStreamContext` from `resumable-stream/generic` runs on Postgres and Realtime without Redis. It uses the new `stream_kv` table and the functions `stream_kv_get`, `stream_kv_set`, `stream_kv_incr` and `stream_kv_publish`. `resumable-stream` is an optional peer.
- New `purgeSchedule` and `purgeOlderThan` options schedule `purge_streams` with pg_cron, which also deletes expired keys.
- `redisStreamStore({ reader })` hides streams that another `owner` opened from `read`, `status`, `isCancelled` and `cancel`.
