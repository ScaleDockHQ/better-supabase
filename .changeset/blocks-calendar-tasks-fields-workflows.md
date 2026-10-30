---
"better-supabase": minor
---

The calendar block takes `options.defaultAlarms`: each calendar keeps the alarms a new event gets when its input sets no `alarms`, in `calendar_default_alarms`, with an anchor time of day for all-day events (default 09:00). The client reads and replaces them with `defaultAlarms(calendarId)` and `setDefaultAlarms(calendarId, alarms)`. `save_calendar_event` also takes an optional `actor`, and `upsert(calendarId, input, { actor })` passes it: a new event's creator and owner are that user, and only the service role may name a user other than the caller.

The tasks block's `update(changes, { atomic: true })` applies a batch in full or not at all, and a `window` change (`{ startAt, endAt }`) moves both dates in one write, so a Gantt drag past the old end no longer fails the date check halfway. `update_tasks` takes `atomic boolean default false`.

In the keyed layout, `custom-fields` takes `on.<type>.keys` with `manage` and `read`, the tenant keys that writing and reading that type's values ask for instead of `custom_fields.manage` and `custom_fields.read`.

Over an app's runs table, the workflows block's `principalKind` and `principalId` columns are optional as a pair. Without them the principal stays in the run's `attributes`, and `run.principal` reads it from there.

Run `better-supabase upgrade` and generate a migration to pick up the new SQL.
