---
"better-supabase": minor
---

`audit.sink()` files events under the categories the SQL modules use: `account.*` and `support.*` events get `security`, and a `category` option maps any other event type to one of `AUDIT_CATEGORIES`.
