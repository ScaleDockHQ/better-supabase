---
"better-supabase": minor
---

An imported quote or invoice can ask for the next free number when its own is taken: put `onTaken: "next_free"` in the item's `data` and the import issues the next number and reports `IMPORT_NUMBER_REASSIGNED`. Without it a taken number still fails the item.

`better-supabase upgrade` rewrites the quotes and invoices modules and the next schema migration replaces two functions. No data migration is needed.
