---
"better-supabase": minor
---

Every block that owns tables now declares the nouns it names its tables, indexes, policies, triggers, functions and events after, so `blocks.<name>.entities` renames them. That covers 43 more blocks, among them `quotes`, `invoices`, `orders`, `inventory`, `bookings`, `forms`, `pipelines`, `hiring`, `ai-chat`, `knowledge`, `agents`, `teams`, `tags`, `templates` and `automations`. Quotes, invoices, orders, bookings and forms are also record types, so comments, attachments, tags and activity can point at them.

Run `better-supabase upgrade` after updating. The new record types widen the subject switches in the blocks that read record titles, and three internal keys move: the orders advisory lock key, the relations lock key and the `better_supabase.restoring_version` setting that `versions` sets while it restores a row.

A config that declares `records.quote`, `records.invoice`, `records.order`, `records.booking` or `records.form` now fails. Remove the entry when it points at the block's own table, or set `blocks.<name>.names.<noun>.subject` to `false` to keep a table of your own.
