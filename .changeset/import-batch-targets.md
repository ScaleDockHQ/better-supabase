---
"better-supabase": minor
---

An import target can name `batch: "schema.function"`, a function `(run uuid, items jsonb) returns jsonb` that writes the batch's items in set-based statements and answers one entry per item. When it raises, every item runs through `write` on its own, so one bad row costs only its own error, and counts, record map rows and errors match the row path (a pgTAP parity test holds it). On the local fixture it is no faster than `write` for customers, because the triggers dominate; it helps targets whose own function does the per-row work.

`better-supabase upgrade` rewrites the `imports` module and the next schema migration replaces `import_apply_batch`. No data migration is needed, and apps without `batch` keep the same generated SQL.
