---
"better-supabase": minor
---

Breaking: `ownership: "adopt"` is removed, because blocks now find your tables themselves. Keep writing your own declarative schema files next to the block files: a block runs over each table your schema already has and creates the rest. To upgrade, run `better-supabase codemod 0.15`, which deletes `ownership` and keeps `tables` and `columns`, then `better-supabase upgrade`, and generate a migration. A config that still sets `ownership` fails validation. Read [Your own schemas](https://bettersupabase.com/docs/blocks/own-schemas).

A table your own schema files create (any declarative file better-supabase didn't write), or a table in the saved snapshot (`source.snapshot`) that no block file or module migration created, is the app's table. Over it, the block skips its `create table`, adds only the columns it needs that your table lacks with `alter table ... add column if not exists` (nullable unless they have a default), and writes its functions, policies and triggers over it. It never revokes your grants or changes your constraints. Text written into a typed column of such a table goes through `better_supabase.as_column_type`, so the column can be an enum or a domain. A module runs over the app's table for each table its spec allows (most block tables); for any other table it refuses to create a table your schema already declares and names the file.

The policies a block adds to your table are named `bsb_<table>_<command>` (such as `bsb_teams_select`) and its triggers start with `bsb_`, so they never replace a policy or trigger of yours with the same name. When your table already keeps `updated_at` current with its own trigger, the block adds no `bsb_updated_at` trigger there. Doctor adds BS347 (warning), for a block policy on your table next to your own policies for that command when none of them repeats its condition, and BS348 (info), for a table whose own `updated_at` trigger the block keeps.

Block files carry a `-- @bsb-hash` line. `upgrade`, `add` and `remove` leave a block file you edited by hand alone and exit 1 naming it, unless you pass `--force`. Block file positions are padded to 3 digits (`900_better_supabase_012_tasks.sql`); `upgrade` renames the 2-digit files and removes block files no installed block writes, when they weren't edited.

`add --adopt` still proposes `tables` and `columns` from the database, but no longer writes `ownership`, and a column the app's table lacks is a warning, since the block's migration adds it. The enum-column check and doctor BS342 now cover the app's tables in every mode, and migration-only options such as `tokenStorage: "plain"` are accepted for a block over a table the app has.

| 0.14                                                         | 0.15                                                           |
| ------------------------------------------------------------ | -------------------------------------------------------------- |
| `blocks.<name>.ownership: "adopt"`                           | delete the key (`better-supabase codemod 0.15`)                |
| `mode: "adopt"` in `BlockConfig` (`BlockMode`)               | `"managed"`, with the app's tables in the layout's `ownTables` |
| a block's table the app lacks, in adopt mode                 | created by the block                                           |
| a column the app's table lacks, in adopt mode                | added by the block (`add column if not exists`)                |
| migration-only options, in adopt mode only                   | accepted for a block over a table the app has                  |
| BS330 "Adopted table without a mapped column"                | BS330 "App table without a column a block uses"                |
| BS344 "Adopted webhook endpoints without a format"           | BS344 "App webhook endpoints without a format"                 |
| `teams_read` on an app-owned `teams` table                   | `bsb_teams_select`                                             |
| `team_members_read` on an app-owned `team_members` table     | `bsb_team_members_select`                                      |
| `bsb_organizations_read` on an app-owned organizations table | `bsb_organizations_select`                                     |
