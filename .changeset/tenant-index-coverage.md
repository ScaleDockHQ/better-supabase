---
"better-supabase": patch
---

Doctor BS204 checks every table in `schemas`, including private schemas, and uses each table's own tenant column. A partial index and an index that contains the column further along each get their own message, with the `create index` statement to add.
