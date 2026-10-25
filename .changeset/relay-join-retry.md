---
"better-supabase": patch
---

`relayRealtimeClient` retries a join that failed for a reason that may pass,
instead of leaving the channel dead until a reload. An `upstream_error` before
the first join, a 5xx answer and a network error are retried with the
exponential backoff up to `maxBackoffMs`, and each failed attempt reports
`CHANNEL_ERROR` once. After a stream fails, the client fetches the stream URL
once to read the status: a 400, 401, 403 or 404 still stops the channel with
`The relay refused <topic>`. `realtimeRelay` answers 503 instead of 403 when
the `realtime.messages` policy check can't reach Postgres.
