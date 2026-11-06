---
"better-supabase": minor
---

Record templates live in the same tables as the records they create. A template is still a row in `templates`. Its content is a versioned body, or rows whose `template_id` is set. Tasks, quotes, invoices, orders and purchase orders opt in with `options.templates`. An app table opts in with the `@bsb template` tag.

While `template_id` is set, numbering, search, pipelines, the state machine and domain events skip the row. Audit still records the edit. `clone_task`, `clone_quote` and `clone_invoice` copy a row and its children. `instantiate_template` creates a record from a published template and writes `template_applications`. `pack_template` and `unpack_template` move a rows template through its version body.
