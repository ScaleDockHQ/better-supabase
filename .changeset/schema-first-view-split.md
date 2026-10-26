---
"better-supabase": patch
---

`migrate schema-first` keeps the grants, comment and policies of a view in the view's own file, and leaves out a `drop view` for a view it writes. `gen` names the events of a table with an `events` tag after its `subject` tag type, as the table's trigger does.
