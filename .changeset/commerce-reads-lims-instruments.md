---
"better-supabase": minor
---

The lims module adds `list_qualified_instruments(tenant, on_date)`, which
returns the asset ids that hold `options.instrumentQualification` on a day, and
the lims block's client calls it through `lims.listQualifiedInstruments({ on })`.
A result form no longer asks `instrumentStatus` once per asset. Without the
option the list is empty. With `options.recognition: true`, the accounting
module adds `list_revenue_recognition_schedules(tenant, limit_count)`, which
returns every revenue recognition schedule of the organization with its row
count and the amount already recognized, so a list of schedules needs no
hand-written read policy. Both functions need the block's read permission.

Run `better-supabase upgrade`.
