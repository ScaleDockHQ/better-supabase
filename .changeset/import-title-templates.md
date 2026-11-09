---
"better-supabase": minor
---

The default titles of imported quotes, invoices, opening balances and checkout invoices come from the new options `quotes.titleTemplate`, `invoices.titleTemplate`, `invoices.openingTitleTemplate` and `orders.titleTemplate`, with `{number}` for the number. The defaults are the old English texts, so nothing changes until you set one, such as `Offerte {number}`.

`better-supabase upgrade` rewrites the quotes, invoices and orders modules and the next schema migration replaces their functions. No data migration is needed.
