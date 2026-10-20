---
"better-supabase": minor
---

Attachments and comments subjects taken from the subject registry now carry the registry's per-action keys: `subjects.<type>.permissions.upload` and `manage` for attachments, `create` and `moderate` for comments. The registry's `read` stays the key for reading the subject itself. `blocks.<block>.options.subjects.<type>.permissions` overrides them key by key.

Doctor `BS345` warns when an attachments subject has no `read` or `upload` key of its own while its table's policies check more than tenant membership, so any member of the tenant would get the files of rows they can't open.
