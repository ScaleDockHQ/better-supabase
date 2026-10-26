---
"better-supabase": patch
---

Blocks that check a record's read permission (tags, attachments, share links, versions, relations and the other modules that take `on`) now honour a `config.records.<type>.permissions.read` with `rows` or `owner`: the key, the provider's row grants and the owner column each grant the read, as `can_subject` does. Before, only the key counted as a tenant key, so `{ key, rows }` refused callers with a row grant (`SHARE_SUBJECT_NOT_FOUND` and similar) and `{ owner }` checked nothing.
