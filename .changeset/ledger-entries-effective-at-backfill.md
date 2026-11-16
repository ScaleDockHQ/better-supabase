---
"better-supabase": patch
---

Ledger version 2: `upgrade` adds `ledger_entries.effective_at` and copies it
from the entry's transaction, so entries posted before the column keep their
transaction's time instead of the upgrade time. Run `better-supabase upgrade`
and apply the migration.
