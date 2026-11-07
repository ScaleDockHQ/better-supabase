---
"better-supabase": minor
---

The contacts block gets `people.mode` (`external` or `tenant`) and the company columns `legal_name`, `registration_id` and `phone`. Document lines get a `unit`, a `discount_kind` and an open-ended `periods` (null), shipments get a `direction` with `setDirection`, document-templates adds the `purchase_order` document type for inventory purchase orders and a `letterhead` text block seed for `nl`, `de` and `fr`. They replace app columns and app SQL that added the same. Invoices are unique by identifier, and `options.uniqueNumber` is removed. Run `better-supabase upgrade`, delete your own columns with these names on block-owned tables, and generate a migration with `supabase db schema declarative sync`.
