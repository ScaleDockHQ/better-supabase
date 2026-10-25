---
"better-supabase": minor
---

`custom-fields` takes `options.layout: "keyed"`: each value row carries its field's `key`, `label` and `type`, and its value in the column of that type (`valueUrl` and `valueEmail` are new optional columns). `set_field_value(tenant, subject_type, subject_id, key, label, type, value jsonb, rank, if_absent)` upserts by record and key and clears the other value columns, `read_field_values` returns typed rows, and the new `delete_field_value(value_id)` records `field_value.deleted`; the client gains `setField`, `readFields` and `deleteValue`. A record type can keep its id in its own column of the values table (`on.<type>.column`), so `subject_type` and `subject_id` can be mapped to `null`. Every layout's `set_field_value` checks the record's `fields` action when `config.records` declares one. The normalized and inline layouts render as before.
