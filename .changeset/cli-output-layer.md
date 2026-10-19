---
"better-supabase": minor
---

The CLI keeps stdout for the command's output. Prompts, spinners, warnings and notices go to stderr, and each stream is colored only when it is a terminal. Outside a terminal, progress prints one plain line instead of a spinner.

- `--no-color` turns colors off on both streams, like `NO_COLOR`.
- `--debug` prints the stack trace of an error, each child command the CLI runs with its exit code, and how long the run and each step took, all on stderr.
- `gen --watch --json` and `spec emit --watch --json` print one result envelope per run on its own line (NDJSON) instead of text.
- `spec emit --watch` now waits for a config that fails to load, the way `gen --watch` does, instead of running with the old one.
- Commands registered with `defineCliCommand` get `log` (`info`, `warn`, `error`, `debug`, `progress`), `paint` and `emit` in their context. `CliIo` takes `stderrColor` and `spinner`, and `Prompter` no longer has a `spinner` method.
