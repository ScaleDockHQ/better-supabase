---
"better-supabase": minor
---

`expose` privileges can grant every column but a few: `select(*, -token_hash)`. `sql sync` turns the list into the columns the table's `create table` declares, in order, and fails when no schema file declares the table or the exclusions leave nothing. `better-supabase/sql` exports `resolveExposeColumns` for apps that render the grants module themselves, and the module refuses an unresolved `*`. Doctor's new warning BS339 reports an excluded column the table no longer has.
