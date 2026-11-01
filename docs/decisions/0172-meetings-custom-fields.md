# 0172: Meetings take custom fields through `extraColumns`

- Status: accepted
- Date: 2026-11-01

## Context

ADR 0154 listed `meetings` among the blocks without `extraColumns`, on the
reasoning that app data goes on the linked tasks and documents. In practice a
meeting carries data of its own (a room code, a cost center, a legal entity),
and the conformance test kept `meetings` on its `NO_FIELDS` list while every
comparable block (`shifts`, `bookings`, `time-tracking`) takes fields.

## Decision

`meetings` takes `options.extraColumns` for the `meetings` table, like other
blocks. `create_meeting` and `update_meeting` already take one `jsonb`
argument, so the values travel under its `fields` key and no new overload
exists. Creation sets them in the insert (so `not null` columns and checks
hold), and an update changes only the keys it names. Reads return them under
`fields`. `createMeetings` accepts a Standard Schema as `fields`, and
`Meeting`, `MeetingInput`, `MeetingChange`, `MeetingDetail` and `Meetings`
carry its type.

Attendees, agenda items, decisions and action items stay fixed records. The
conformance test drops `meetings` from `NO_FIELDS`.

## Consequences

- A config without `extraColumns` renders the same SQL as before except for
  the `fields` type check, which is skipped without extra columns.
- `Meeting` gains a required `fields` property (empty without extra columns).
  Code that builds `Meeting` values by hand adds `fields: {}`.
