---
"better-supabase": minor
---

Add `better-supabase automations list`, which prints the automations the installed blocks ship, and `--explain`, which says which block's event starts each one and what its actions do. Field history now also watches columns that a block entity declares in `subject.history`, and the `events` and `audit-reads` table tags write their SQL through `table enable`.
