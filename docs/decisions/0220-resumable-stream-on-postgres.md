# 0220: Run resumable-stream on Postgres and match its semantics

- Status: accepted
- Date: 2026-11-03

## Context

The AI SDK resumes a stream through `consumeSseStream` and the
`resumable-stream` package, which needs a Redis-like publisher (`get`, `set`
with a TTL, `incr`, `publish`) and a subscriber. Our `resumableStreamContext`
had the package's method names but different results: `null` for a missing
stream and a replay for a finished one. The Redis store also let any reader
open any stream.

## Decision

- `resumableStreamContext` returns `undefined` for a missing stream and `null`
  for a finished one, and adds `resumableStream`. `replayFinished` keeps the
  old replay.
- `better-supabase/streams/resumable` provides `postgresPublisher` and
  `postgresSubscriber`. The key-value functions live in the `streams` module
  (version 3, service role only). `stream_kv_incr` raises Redis's error text on
  a non-integer, which is how the package detects `DONE`. Publishing uses
  `realtime.send` on a private topic.
- `resumable-stream` is typed structurally and is an optional peer.
- `purgeSchedule` registers the purge with pg_cron when it exists.
- `redisStreamStore({ reader })` applies the stream's `owner` to reads.

## Consequences

Apps on Supabase run resumable chat streams without Redis. Code that relied on
a replay of a finished stream sets `replayFinished: true`. The Realtime
subscriber needs a service-role client.
