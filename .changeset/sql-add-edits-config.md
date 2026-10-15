---
"better-supabase": minor
---

`better-supabase sql add` lists the new modules in `blocks` of the config file, as `name: {}` in an object or a name in a list, and edits `better-supabase.config.json` too. When `blocks` isn't a literal it can follow, it leaves the file alone and prints the entries to add. `--dry-run` says what it would add.
