---
"better-supabase": minor
---

Transactional outbox. The new `outbox` SQL kit module stores events with `emit_event(type, payload, subject, tenant, key, source)` in the writing transaction, deduplicates by key per tenant, adds `track_events(table)` row triggers and keeps events for `outbox_history` until `purge_outbox`. Named consumers read in order with their own cursor and a lease, and a claim never skips an event whose transaction is still open. The `organizations` and `support-sessions` modules write their events to it once it's installed. `createOutbox` in `better-supabase/jobs` emits, registers consumers, relays events as CloudEvents to any `EventSink` and serves `relayRoute` for a cron caller. The module supports `mode: 'adopt'` for an existing events table.

The `defaultSource` option fills the source of `emit_event` calls that pass none, and `kitSource` sets the source kit modules write (`better-supabase/{module}` by default), so an adopted events table with a check on its source column keeps working. Adopt mode still creates the consumers table, since an existing app has no cursors yet.
