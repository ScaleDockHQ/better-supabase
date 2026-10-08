---
"better-supabase": minor
---

`sql.modules.tenant.options.sameTenant` can match a column reached through another reference of the written row. A `match` key written `<reference column>.<column>`, with `through: { <reference column>: "schema.table" | { table, column } }`, compares that column of the row the reference points at with the referenced row's column, so a quote asset must belong to the quote's customer even though the asset row only holds `quote_id`. The trigger also runs when the reference column changes.
