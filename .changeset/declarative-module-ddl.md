---
"better-supabase": minor
---

Module files are declarative DDL. They no longer write `drop policy if exists`, `drop function if exists` or `drop trigger if exists`, `if not exists` on tables and indexes, or `if not exists` on the columns of tables the block owns, so a schema diff reads each file as the end state. Run `better-supabase upgrade` and commit the result. The migrations workflow still writes statements that can run again. `renderPolicy` no longer takes a `drop` option.
