---
"better-supabase": minor
---

Blocks no longer add columns to a table you create: a feature whose column your table lacks is off. Upgrade: run `better-supabase codemod owned-columns` and commit the `*.block-columns.sql` files before `better-supabase upgrade`, then check doctor BS622. A database that has the columns changes nothing. The migration note is in the 0.57 to 0.58 guide.
