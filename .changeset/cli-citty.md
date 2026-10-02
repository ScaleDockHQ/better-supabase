---
"@better-supabase/cli": minor
---

The CLI runs on citty. `init` and `add` ask for the casing, the integrations and whether to overwrite files when they run in a terminal; `--yes`, CI and piped input skip the questions. Output is colored in a terminal (`NO_COLOR` turns it off), database work shows a spinner on stderr, and `gen --check`, `introspect --check` and `sql sync --check` print a unified diff of each stale file.

`registerCommand` takes a command from the new `defineCliCommand`, and `list()` splits list options. The 0.2 form, `registerCommand(name, command, help)`, still works and is deprecated. `help()` replaces the `HELP` constant.
