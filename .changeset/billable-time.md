---
"better-supabase": minor
---

Add the `billable-time` block (`better-supabase/blocks/billable-time`). It keeps an hourly rate card per organization, member and record, previews the unbilled time with `unbilled()`, and bills it as lines on a draft invoice with `invoice()`, in bigint minor units. Billed entries can't be changed or deleted until the invoice is voided, and the `billableTime` section shows a record's unbilled time. Install it with `better-supabase add billable-time`; it needs `time-tracking` and `invoices`.
