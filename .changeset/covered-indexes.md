---
"better-supabase": minor
---

A block over your own table no longer creates a plain index that one of your indexes, primary keys or unique constraints already covers with the same leading columns. `add` and `upgrade` read those indexes from your schema files and the saved snapshot (`ownIndexes` in the module layout), and `better-supabase/sql` exports `declaredIndexes`.
