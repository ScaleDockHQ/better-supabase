---
"better-supabase": patch
---

`better-supabase codemod` runs when the config file fails to load, so `codemod 0.9` can migrate a config that still sets `sql.modules`. It walks the directory that holds the discovered config file, or `--cwd` when there is none. Commands built with `defineCliCommand` opt in to the same behaviour with `runsWithInvalidConfig: true`.
