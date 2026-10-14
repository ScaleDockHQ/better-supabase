---
"better-supabase": minor
---

Adds the calendar block (`better-supabase/blocks/calendar` and `better-supabase/blocks/calendar/react`, SQL module `calendar`). It stores calendars, events with RFC 5545 recurrence, overrides and attendees. `occurrences()` expands series with the reminders block's `expandRule`, `editOccurrence` and `editFollowing` override one occurrence or split a series, `importIcs` and `exportIcs` read and write iCalendar files, and a share link to a calendar serves an iCal feed. `useCalendar` returns events in the shape an event calendar renders.

`expandRule` takes a `window` so long-running series expand only the occurrences in a range, and `revoke_share_link` no longer fails with an ambiguous `id` column.
