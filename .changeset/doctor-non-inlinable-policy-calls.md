---
"better-supabase": patch
---

Doctor BS386 now flags a select policy that calls a `security definer` function, or one with a `set` clause, once per row, even when it is a stable SQL function such as `can_note(notes, 'read')`. Postgres never inlines such a function, so a list pays one call per row. The call is still accepted as the `or` fallback after a set check, as in `id in (select note_ids('read')) or can_note(notes, 'read')`. It also no longer flags a set helper in the `from` of a subquery that is joined `lateral` or wrapped in parentheses, or one whose arguments read a column of another `from` item such as `member.id`.
