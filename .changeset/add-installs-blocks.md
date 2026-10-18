---
"better-supabase": patch
---

`better-supabase add <block>` is the documented way to install a block: it writes the module files like `sql add`, then wires the block's client into `lib/blocks.ts` and prints the glue command. `add` now takes `--tests-dir`, so it accepts every option `sql add` does. `sql add` stays as the low-level command that writes only the SQL files and the config entry. The header of generated module files, the doctor hints for grants, MFA and realtime triggers, and the Data API grant error now name `better-supabase add`. Re-run `better-supabase sql sync` to refresh the header in existing module files; it is a SQL comment, so the schema doesn't change.
