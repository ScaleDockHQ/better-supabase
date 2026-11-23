---
"better-supabase": minor
---

Breaking: `invoice_open_items` holds unallocated payments next to open invoices, so its
`document_id` no longer references `invoices`; filter on `document_type` in your own queries. The
store now matches the fold: its triggers and `rebuild_open_items` count the `credited` status,
refresh on a charge, a kind change and a party change, and keep future-dated invoices, which the
reads show from their issue date. `open_items_drift(tenant)` lists rows that differ from the
fold, `import_integrity` reports them, and doctor rule BS638 names the organizations to rebuild.
The invoices block moves to version 4, and the data migration rebuilds every organization. One
party's 100 open items read in 1.4 ms instead of 2.6 ms on the local stack (ADR 1214).
