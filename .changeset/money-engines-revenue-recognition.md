---
"better-supabase": minor
---

`accounting` can recognize revenue over time. With `options.recognition: true`, `schedule_revenue_recognition` splits an amount over the months of a service period, books the deferral against the new `deferred_revenue` account (`2200` in the generic chart) and `list_revenue_recognition` reads the rows. The `revenue_recognition` period kind posts each month's row when that month closes. The two `accounting_recognition_*` tables always exist, so existing apps run `better-supabase db diff` to pick them up.
