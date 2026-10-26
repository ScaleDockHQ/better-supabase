---
"better-supabase": minor
---

A `config.records.<type>.permissions.<action>` entry takes `also`, a permission key the caller must hold as well, in the row's tenant or on the record's scope: `{ key, rows, also }` asks for a row grant (or the key) and the tenant key both. `can_subject`, `can_subject_for` and the blocks' record read checks honour it.
