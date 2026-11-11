---
"better-supabase": patch
---

Lazy server tables (`gen.serverTables: "lazy"`) now load the tables a call reaches through relations before the query is built, so includes, nested includes, relation filters, counts and `orderBy` across a relation no longer fail with `unknown table` in a fresh process. `specTables` no longer caches the fallback for a table that has not loaded yet.

`blocks.<name>.indexes.skip` and tables mapped to `null` keep the comments above a dropped statement, so a module file whose first statement is skipped keeps its `-- better-supabase module` and `@bsb-block` header, and the next `upgrade` reads the right version.
