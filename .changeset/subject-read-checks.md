---
"better-supabase": minor
---

A subject permission entry takes `check`, the schema-qualified name of a SQL function `(subject_id <idType>) returns boolean` that decides the action for the caller. Alone it decides the action; next to `key`, `rows` or `owner` it must return true as well. `can_subject` and the blocks that check record reads (tags, attachments, relations and the others that take `on`) call it, and `can_subject_for` returns false for such an action, because it can't run the function for another user.

A subject type also takes `readAccess: "record"`: `custom-fields` then shows that type's values only to members who can read the record, in every layout, while the other types keep `custom_fields.read`.

`driveSubject()` uses both. Its `read` action asks `drive.read` and the new `drive_node_readable(node)`, its `fields` action asks `drive_node_writable(node)`, and it sets `readAccess: "record"`. A member with `drive.read` but no grant on a node can no longer tag it, attach to it or read its custom field values. Run `better-supabase upgrade` and generate a migration to pick up the new SQL.
