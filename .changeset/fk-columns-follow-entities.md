---
"better-supabase": minor
---

The foreign key columns that point at a task or an activity are renamed: `work_item_id` is `task_id` in
`task_checklist_items` and `task_assignees`, and `engagement_id` is `activity_id` in `engagement_subjects`,
`engagement_recordings`, `engagement_notes` and `mail_threads`. `better-supabase upgrade` renames them in the
block tables, and a column of an entity you renamed or an adopted table keeps its name. Rename the columns in
your own SQL, views and policies; `codemod 0.47` lists the lines that use the old names.
