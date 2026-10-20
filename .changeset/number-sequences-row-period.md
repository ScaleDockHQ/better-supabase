---
"better-supabase": minor
---

`number-sequences` takes the period of a new number from the row: with `periodColumn` set, the trigger reads the period and the date tokens of the format from that column (a `date`, `timestamp` or `timestamptz`, in UTC), such as an invoice's issue date, and falls back to the time of assignment while it is null. `sync_number_sequences` reads a `date` column in UTC too.
