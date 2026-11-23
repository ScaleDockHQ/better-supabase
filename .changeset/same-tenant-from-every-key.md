---
"better-supabase": minor
---

Same-tenant checks now come from every foreign key between two tenant tables, composite keys included: the first column leads and the others are checked as `match` pairs. A `@bsb same-tenant` tag follows the nullability of the referenced tenant column instead of always letting a row with no tenant pass, takes `tenant=`, `parent-tenant=` and `shared=true|false`, and works on any foreign key that holds the column. `better-supabase codemod table-tags` moves a `blocks.memberships.options.sameTenant` entry into a tag when the tag renders the same trigger statement, and lists each entry it leaves with the reason. See ADR 1192 and the [0.82 to 0.83 guide](https://bettersupabase.com/docs/migration/0.82-to-0.83).
