---
"better-supabase": minor
---

Add `blocks.invoices.permissions.settle`, a second key that may record a payment for an invoice's whole open balance (or replay one already recorded) but not a part, so a "mark paid" permission works next to a finer "record payment" one. Without it, payments check `payment` as before.
