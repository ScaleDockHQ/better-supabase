---
"better-supabase": patch
---

`doctor` BS386 no longer flags a volatile set helper in the `from` of a policy subquery when its arguments read no column of the row, such as `id in (select t.id from thread_ids('key') as t(id))`. Postgres calls that function once and rescans its result. A helper whose arguments read the row is still flagged.
