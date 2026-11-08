---
"better-supabase": minor
---

`options.on` of the time-tracking block lists the record types an entry can be tracked on (`TIME_SUBJECT_INVALID` for another type), replacing an app trigger that did the same. The tasks block takes `locked` as an optional column, so a table without a lock maps it to `null`. Run `better-supabase upgrade` and generate a migration with `supabase db schema declarative sync`.
