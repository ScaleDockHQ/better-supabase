---
"better-supabase": minor
---

`config.records.<type>.permissions.<action>` takes `{ key, rows, owner }` besides a key: `rows` grants the action on the rows of a provider resource the caller holds `key` on, through the new `rowsWith` provider template (`rowsWithFor` for `can_subject_for`), and `owner` grants it to the user a uuid column names. `can_subject` and `can_subject_for` check every form. Blocks that act on a record ask the record's own action when its type declares one: `tags` checks `write` in `tag` and `untag`.
