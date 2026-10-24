---
"better-supabase": patch
---

Over your own tables, the `profiles` block no longer adds an `avatar_path` column it doesn't use, and `forms` scores submissions unless `columns.submissions` maps `score`, `maxScore` or `passed` to `null`. `add --adopt` lists a required column the block adds as `<column> (the block adds it)` instead of `null`. Doctor no longer reports BS309 for an old table or column name on a table of your own, which keeps your names.
