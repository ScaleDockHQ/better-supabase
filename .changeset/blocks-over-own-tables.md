---
"better-supabase": minor
---

Blocks now leave alone every table your schema already has. A table your own schema files create (any declarative file better-supabase didn't write), or a table in the saved snapshot (`source.snapshot`) that no block file or module migration created, is the app's table: the block skips its `create table`, adds the columns it needs with `alter table ... add column if not exists` (nullable unless they have a default), and writes its functions, policies and triggers over it. Text written into a typed column of such a table goes through `better_supabase.as_column_type`, so the column can be an enum or a domain.

Block files carry a `-- @bsb-hash` line. `better-supabase upgrade`, `add` and `remove` leave a block file you edited by hand alone and report it, unless you pass `--force`. Block file positions are padded to 3 digits (`900_better_supabase_012_tasks.sql`); `upgrade` renames the 2-digit files and removes block files no installed block writes, when they weren't edited.

A module runs over the app's table for each table its spec allows (most block tables). For any other table it refuses to create a table your schema already declares and names the file, so rename yours or map the block's table to another name in `blocks.<name>.tables`. The enum-column check and doctor BS342 now cover the app's tables in every mode, and migration-only options such as `tokenStorage: "plain"` are accepted for a block over a table the app has.

Breaking: `ownership: "adopt"` is removed. A block now leaves alone every table your schema already has, so the key has nothing left to say, and the config fails validation until you delete it. `better-supabase codemod 0.15` removes it and keeps `tables` and `columns`. `add --adopt` still proposes `tables` and `columns` from the database, but no longer writes `ownership`, and a column the app's table lacks is a warning, since the block's migration adds it.

| 0.14                                               | 0.15                                                           |
| -------------------------------------------------- | -------------------------------------------------------------- |
| `blocks.<name>.ownership: "adopt"`                 | delete the key: the block finds the app's tables itself        |
| `mode: "adopt"` in `BlockConfig` (`BlockMode`)     | `"managed"`, with the app's tables in the layout's `ownTables` |
| a block's table the app lacks, in adopt mode       | created by the block                                           |
| a column the app's table lacks, in adopt mode      | added by the block (`add column if not exists`)                |
| migration-only options, in adopt mode only         | accepted for a block over a table the app has                  |
| BS330 "Adopted table without a mapped column"      | BS330 "App table without a column a block uses"                |
| BS344 "Adopted webhook endpoints without a format" | BS344 "App webhook endpoints without a format"                 |
