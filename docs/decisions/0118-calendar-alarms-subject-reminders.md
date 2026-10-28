# 0118: Store calendar alarms as event data; schedule reminders on any subject from a block timer

- Status: accepted
- Date: 2026-10-28

## Context

Calendar apps carry `VALARM` components on their events, and `importIcs`
skipped them, so a round trip through better-supabase lost every alarm. The
reminders block already sent per-user reminders, but only before the
occurrences of a recurrence rule, so a task with a due date or a one-off
"remind me at 9" had no rule to hang on. Planning the deliveries was left to
the app: `planReminderDeliveries` returned jobs, and nothing enqueued them.

## Decision

Alarms are event data. The calendar module adds `calendar_event_alarms`
(`src/sql/modules/calendar-alarms.ts`): one row per alarm with a `method`
(`display`, `email` or `audio`), either an `offset_minutes` offset before the
start or end or an absolute `trigger_at`, a `repeat_count` with
`repeat_minutes`, and an optional `user_id` for a member's own alarm.
`save_calendar_event` replaces an event's shared alarms when the item has
`alarms`, the read functions return them, and `parseIcs` and `toIcs` map them
to `VALARM` (`src/blocks/calendar/alarms.ts`). The table is tenant-scoped,
gets the restrictive tenant policies (ADR 0099), and is adoptable or
removable through `tables.alarms` (ADR 0098).

There is one alarm model and one feed path. An alarm is a `CalendarReminder`,
the `{ method, offsetMinutes }` shape the feed already used for an app's
alarm table and the creator's reminders, where a positive offset fires
before the event. The feed writes each event's alarms, with the link
creator's own rows, and the creator's reminders under `reminders`, through
the same `alarmLines` writer. The feed's former `options.feed.reminders`
table option is replaced by adopting `tables.alarms`; the module refuses it
with a message that names the new keys.

Reminders are per-user delivery, kept apart from alarms. A reminder now fires
before each occurrence of its subject's rule, before the time in the
subject's `on.<type>.at` column, or once at its own `remind_at`.
`list_reminder_schedule` returns all three as rows with a `dtstart`, a
`tzid` and an `rrule` (a one-time row is `FREQ=DAILY;COUNT=1`), so one
expander plans them. `save_reminder` checks the subject against the types in
`on`, or in `config.subjects` when `on` is unset, through the subject
registry's read rule. `reminders.schedule()` enqueues one `reminders.deliver`
job per occurrence due in the horizon with `enqueueOnce`, keyed by reminder
and occurrence, and the block declares it as the `reminders.schedule` block timer,
so the queue's dedupe and `mark_reminder_sent`'s
per-occurrence dedupe together send each occurrence once.

## Alternatives considered

- Keep a separate alarm table next to the feed's app alarm option. Two
  shapes for the same `VALARM` would need two writers and two sets of docs,
  and the feed would read only one of them.
- Fire calendar alarms from the server as reminders. An alarm belongs to the
  event and every reader's client fires it; turning it into a server send
  for every attendee would notify people who never asked.
- One `reminders.schedule` queue with its own cron. The block timers already
  run on `block_ticks` with one schedule per timer; a second mechanism would
  need its own setup docs and its own dead letter.
- Store a one-time reminder as a rule row with `COUNT=1`. It would claim the
  subject's single rule slot (`recurrence_rules` is unique per subject) and
  clash with the calendar's mirrored rule.

## Consequences

Alarms survive an iCalendar import and export, and a reminder works on any
registered subject without the app writing a rule. `save_reminder` gains a
`remind_at` argument with a default, so positional calls keep working; it
also refuses a subject of a registered type that doesn't exist or that the
caller can't read, which it used to accept. `schedule()` skips rules kept in
columns (`ruleFormat: "columns"`) and counts them, since it can't expand
them; we revisit that when the column format has a TypeScript reader. An app
that used `options.feed.reminders` maps its table as `tables.alarms` instead;
the table then needs a tenant column, and a row's `email` method exports as
an email alarm rather than a display one.
