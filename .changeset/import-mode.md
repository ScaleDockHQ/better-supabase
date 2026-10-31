---
"better-supabase": minor
---

Import runs now write in an import mode. `import_upsert_batch` begins an import session for its batch,
and `better_supabase.begin_import_session(run)` does it for a transaction you control (service role
only, on a running run). `better_supabase.import_run()` returns the run id inside a session and only
to the service role, so a user session can't turn the mode on.

In the mode the outbox applies `blocks.imports.options.events` (an event type or `default` to
`skip`, `tag` or `emit`, skipping what is not listed), the audit log tags entries as `integration`
with the correlation id `import:<run>` and `options.audit: "summary"` writes one entry per entity
instead of one per row, and a state machine accepts any declared status on insert with one `imported`
history row and no event. Notifications, accounting auto-posting and the stock taken for paid orders
and shipped shipments are not run. SQL modules read the condition with `ctx.importing()`.

An existing app changes behavior only inside an import run. Apply the new migration with
`better-supabase upgrade`.
