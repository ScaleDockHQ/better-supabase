---
"better-supabase": patch
---

Fixes from the 0.85 adopter gate. The generated audit pgTAP file no longer checks a table that a `drop table` inside a `do` block removed, and a dropped `bsb_audit` trigger counts as `unaudit`. A block with `audit: false` gets no row audit triggers on its tables. The invoices module grants `rebuild_open_items` to the service role only and grants `open_items_drift` and `open_items_page` once, and the API schema writes one wrapper per function when a module grants it twice. A view-backed search subject (`search.from`) re-indexes when its `exclude` column, such as `archived_at`, changes, where its own table has that column. Doctor no longer reports extension types (`citext`, `halfvec`), `serial` types or `pg_temp` tables under BS721, `approvals: false` with `standaloneApprovals` on expenses under BS706, or an optional-column mapping that changes the render under BS427. The 0.84 to 0.85 guide says to run `add --adopt` after the schema diff.
