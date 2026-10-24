---
"better-supabase": minor
---

Blocks now leave alone every table your schema already has. A table your own schema files create (any declarative file better-supabase didn't write), or, under `workflow: migrations`, a table in the saved snapshot that no module migration created, is the app's table: the block skips its `create table`, adds the columns it needs with `alter table ... add column if not exists` (nullable unless they have a default), and writes its functions, policies and triggers over it. Text written into a typed column of such a table goes through `better_supabase.as_column_type`, so the column can be an enum or a domain.

Block files carry a `-- @bsb-hash` line. `better-supabase upgrade`, `add` and `remove` leave a block file you edited by hand alone and report it, unless you pass `--force`. Block file positions are padded to 3 digits (`900_better_supabase_012_tasks.sql`); `upgrade` renames the 2-digit files and removes block files no installed block writes, when they weren't edited.

Only modules that support adopt mode today run over a table the app has. Any other module refuses to create a table your schema already declares and names the file, so rename yours or map the block's table to another name in `blocks.<name>.tables`. The enum-column check and doctor BS342 now cover the app's tables in every mode, and migration-only options such as `tokenStorage: "plain"` are accepted for a block over a table the app has.
