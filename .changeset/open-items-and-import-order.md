---
"better-supabase": minor
---

`open_items_for_party` reads the invoice's stored `paid_total` when `as_of` is omitted or today, and still replays the ledger for a past date. An import batch applies items in `data.orderBy`, then `data.readAt`, then key order.

Gen treats a function body that returns `coalesce(...)` as not null when the catalog includes the body. A `functions` `notNull` entry or an `@notNull` tag still wins.

`better-supabase upgrade` rewrites the invoices and imports modules. The next schema migration replaces those functions. No data migration is needed.
