---
"better-supabase": minor
---

Calendar events keep their alarms, and reminders work on any subject.

- Calendar: a new `calendar_event_alarms` table holds each event's `VALARM`s (an action, a trigger offset or absolute time, and a repeat). `upsert` takes `alarms`, reads return them, `importIcs` reads them and `exportIcs` and the feeds write them. Map `tables.alarms` to your own table or set it to `null`.
- Reminders: `upsert(subject, { at })` sets a one-time reminder (a new `remind_at` column), and `on.<type>.at` names a subject's time column, such as a task's `due_at`, for subjects without a recurrence rule.
- Reminders: `schedule()` enqueues one `reminders.deliver` job per occurrence due in the next day on the new `jobs` option, once per reminder and occurrence. The block declares it as the `reminders.schedule` timer, and `reminderJobSchema` types the delivery queue.
- `save_reminder` now refuses a subject of a registered type that doesn't exist in the organization or that the caller can't read (`REMINDER_SUBJECT_NOT_FOUND`), and with `on` set, a type `on` doesn't list (`REMINDER_SUBJECT_UNSUPPORTED`). Run `better-supabase upgrade` and generate a migration.
