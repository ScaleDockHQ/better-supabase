---
"better-supabase": minor
---

The calendar block gains `calendar.bootstrap` and the SQL function
`calendar_bootstrap`, which read a calendar page in one database call: the
organization's calendars, the occurrences of a range, the occurrences of a
second range and the caller's reminders on events. Run `better-supabase upgrade`
and apply the migration it generates to get the function in an installed block.
`search` also stops computing a full-text rank for rows that only the trigram
index matched, which halves its time on a corpus where most documents match by
trigram; its results and scores do not change.
