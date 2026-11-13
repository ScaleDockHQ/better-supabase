---
"better-supabase": patch
---

The audit test generator follows a renamed table. A migration that runs `alter table ... rename to` now moves the table's `audit()` or `bsb_audit` trigger registration to the new name, so `gen` and `upgrade` stop writing pgTAP checks for the old name, which no longer exists, and stop reporting the generated audit test as edited by hand once it is fixed.
