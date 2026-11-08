---
"better-supabase": minor
---

A column your own schema file adds to a block's table (`alter table ... add column`) is a field of that block: its functions read and write it, and the block adds none of it. `better-supabase codemod extra-columns` moves `blocks.<name>.options.extraColumns` (and the `*ExtraColumns` options) into the file that already alters the table, or into `<table>.ext.sql`, and removes the options from the config.
