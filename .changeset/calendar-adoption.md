---
"better-supabase": minor
---

The calendar block runs over an app's own calendar tables, with five opt-in options. A config without them renders the same SQL as before.

- `options.access`: per-calendar access. Calendars get a `visibility` (`shared` or `private`) and an owner, events a `visibility` and an owner, and `tables.grants` gives a member `viewer` or `editor` access. Every write function checks the calendar or event it changes, the read policies hide private calendars and events from other members, and feeds and free/busy never show a private event's details. `options.accessFunctions` names app functions that decide instead. Client: `setGrant`, `removeGrant`, `grants`.
- `options.userFeed`: a share link whose subject is a user (`calendar_user`) serves every calendar that user can read as one feed (`calendar_user_feed`, client `userFeed`).
- `options.rdates` adds an `rdates` column of extra occurrence starts, and `options.recurrence: "table"` keeps rules and dates in `tables.rules` (an `rrule` text column or structured columns) and `tables.recurrenceDates`. Saving, cancelling, splitting, importing and every read go through them. `expandOccurrences`, `parseIcs` and `toIcs` read and write `RDATE`.
- `options.attendeeKey: "any"`: an attendee is a user, an email or a subject record, with `organizer` and `optional` flags; `set_calendar_attendee(event_id, attendee)` updates or inserts without a unique constraint and `remove_calendar_attendee(attendee_id)` removes one (client `removeAttendeeById`). The old signatures keep working.
- `options.calendarDetails`: calendars get `description`, `rank` and `isDefault`, `createCalendar` takes them, and `update_calendar(calendar_id, attrs)` (client `updateCalendar`) changes them and records `calendar.updated`.

An owner column of another type, such as a `uuid`, takes `values.calendars.ownerId: {}`, so `create_calendar` casts the owner to it.
