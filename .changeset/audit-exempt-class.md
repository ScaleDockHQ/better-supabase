---
"better-supabase": minor
---

`blocks.audit.options.exempt` takes `{ class: "no-tenant-column", reason }`, which leaves out every table that has no tenant column, in place of one entry per table. Doctor BS315 asks for the reason, as it does for a table glob.
