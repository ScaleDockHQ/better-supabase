---
"better-supabase": minor
---

`stream_kv` is `stream_entries`, `invoice_e_endpoints` is `e_invoice_endpoints` (table and function) and `workflow_step_library` is `workflow_step_templates`. Run `better-supabase codemod naming` to write the migration that renames the tables of an installed app with their constraints, indexes and policies, then `upgrade`; no data moves. The `set_config` keys of generated triggers moved from `bsb.<key>` to `better_supabase.<key>` and last one transaction.

| Old                             | New                                                     |
| ------------------------------- | ------------------------------------------------------- |
| `stream_kv`                     | `stream_entries`                                        |
| `invoice_e_endpoints`           | `e_invoice_endpoints`                                   |
| `workflow_step_library`         | `workflow_step_templates`                               |
| `bsb.recorded`, `bsb.lane_move` | `better_supabase.recorded`, `better_supabase.lane_move` |
