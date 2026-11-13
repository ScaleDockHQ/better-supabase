---
"better-supabase": minor
---

Comment counters and search lists now check record access once per list
instead of once per row. The subjects module adds `can_subjects(subject_type,
subject_ids, action)`, which returns the ids the caller can act on in one
read of the record's table. `comment_counts` uses it and then finds the
records' conversations by key, through the new `comment_count_keys`;
`comment_count_rows` is removed. `search_page`, `search_recents` and
`search_favorites` check each batch or record type with one call. The results
don't change.

Run `better-supabase upgrade` (subjects 2, comments 10, search 5).
