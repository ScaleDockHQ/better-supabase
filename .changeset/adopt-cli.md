---
"better-supabase": minor
---

`better-supabase adopt <block> --from <schema.table>` maps a block onto tables the app already has. It reads the tables like `introspect`, matches the block's logical tables and columns to them (including likely renames such as `organization_id` for `tenant`, and `null` for optional columns the table lacks), prints the mapping with a doctor-style report of what can't map, and writes `blocks.<block>` in adopt mode when everything maps. `--dry-run` writes nothing and `--json` prints the entry, the mapping and the report.

`apply --preset <code> --adopt` proposes the same mapping for every block of the preset that has a table under its default names, shows it before the config diff, and writes nothing when one of those tables can't be adopted. `apply` now also takes `--snapshot`, `--db-url-stdin` and `--project-ref`, and `--json` prints the config it writes and the blocks it adopted.
