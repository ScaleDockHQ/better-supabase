---
"better-supabase": patch
---

The `accounting` block now books invoice charges and write-offs. Adding a charge books receivable
against revenue, removing it or voiding the invoice reverses the entry, and `writeOff` books the
open balance as an expense. Named block instances book too when their `uses` binds an accounting
instance. `project_costs` leaves billed time out of the total when its revenue is already booked
to the project dimension. Two data steps backfill project dimension values for existing projects
and seed the missing `disposal_gain` and `disposal_loss` accounts. Run `better-supabase upgrade`
and apply the new migrations.
