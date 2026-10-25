---
"better-supabase": patch
---

`relayRealtimeClient` retries a first join that failed instead of leaving the
channel dead until a reload, for example while a local Realtime service starts.
Until the channel joins, each failed attempt reports `CHANNEL_ERROR` and is
retried with the exponential backoff up to `maxBackoffMs`; an `end` event before
the join (`upstream_error`) goes through the same backoff instead of the fixed
`retry:` loop. `timeoutMs`, now counted from `subscribe()`, caps this phase:
the channel then reports `TIMED_OUT` with the status and problem detail of one
final request, and stops.

`realtimeRelay` no longer reports a check that can't run now as a denial. A
throw from `authorize`, a policy check that can't reach Postgres and a session
with a `network` or `unexpected` error (such as `JWKS_FETCH_FAILED`) end the
stream with the new `unavailable` reason, which the client retries; a send
answers 503. Refusals keep their 400, 401, 403 or 404.

`better-supabase upgrade` also renames `bs_` event triggers, such as the audit
block's `bs_audit_forget_dropped`, so a full declarative diff no longer drops
and recreates them.
