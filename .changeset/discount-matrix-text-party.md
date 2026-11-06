---
"better-supabase": patch
---

The discount matrix on quotes, invoices and orders now casts the party to text before it calls `resolve_line_discount`. A uuid company or customer column no longer fails with `function resolve_line_discount(uuid, uuid, ...) does not exist`.
