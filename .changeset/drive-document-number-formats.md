---
"better-supabase": minor
---

Controlled document types in `blocks.drive.options.control.types` can set a number format with `{
name, numberFormat }`, such as `SOP-{n:4}`. A type with a format counts from its own sequence, and
the other types keep the shared `DOC-{n:5}` sequence. Apply the new migration with
`better-supabase upgrade`.
