---
"better-supabase": patch
---

Doctor BS386 accepts a per-row check after an `in (select ...)` set check only when the check passes the whole row, as in `id in (select note_ids('read')) or can_note(notes, 'read')`. A check that reads a column after an unrelated set check, such as `employee_id in (select own_employee_ids()) or is_decider(id)`, is flagged again.
