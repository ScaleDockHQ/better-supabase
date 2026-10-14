---
"better-supabase": patch
---

Doctor's BS213 check no longer counts a subject's `deletedAt` column from `config.subjects` as a column that grants access. `can_subject` runs as the caller and only hides soft-deleted rows, so a user who may write that column could already read the row. A column the authorization provider lists in `decidingColumns` still counts.
