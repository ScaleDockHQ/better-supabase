---
"better-supabase": patch
---

The `reserved-slugs` module grants `select` on `reserved_slugs` to `service_role`, so service-role writes to a table with `track_slug` no longer fail with `42501`. `sql.modules["reserved-slugs"].options.minLength` and `maxLength` (1 and 63 by default) bound a slug's length; `slug_problem` returns `invalid` outside them.
