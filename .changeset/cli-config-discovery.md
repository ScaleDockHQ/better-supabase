---
"better-supabase": minor
---

The CLI finds `better-supabase.config.*` in the working directory or the nearest parent directory that has one, up to the directory that holds `.git`, so a config at the repository root works when a command runs from a package without `--cwd`. Paths inside a discovered config are relative to the config file; `--cwd` and `--config` keep their meaning. `doctor --format github` and `--format sarif` report file paths relative to the repository root, so annotations land on the right files from any directory.
