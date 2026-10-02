---
"@better-supabase/cli": minor
---

Breaking: the CLI follows one set of conventions for output, errors, prompts and secrets.

- `--db-url` is removed from `gen`, `introspect`, `doctor` and `seed`, because a connection string holds the password and arguments end up in shell history and the process list. Set `$DATABASE_URL` or `source.dbUrl`, or pipe the URL in with `--db-url-stdin`.
- `--json` is a global option. It prints one JSON document on stdout: the command's result, or RFC 9457 Problem Details with a `code` when it fails. `doctor --format json` becomes `doctor --json`.
- `--yes` (`-y`) is a global option. Prompts never run under `--json`, `--yes` or `CI`.
- Exit codes are 0 for success, 1 for a failure and 2 for a usage, config or environment error. Every error code has a section on [the errors page](https://bettersupabase.com/docs/cli/errors).
- A mistyped command gets a suggestion: `Did you mean "gen"?`.
- `better-supabase.config.*` loads through c12 and is checked against a schema; an unknown key or a wrong value stops the run with each problem's path. `DATABASE_URL` and `SUPABASE_API_URL` must be URLs.
- `run()` no longer reads `process.env`: pass `run(argv, { env: process.env })`. `CliIo.env` and `CliIo.now` are removed, and `CliIo.stdin` is new.
- New exports: `CliError`, `CLI_ERRORS_URL`, `commandNames`, and the `CliEnv`, `CliProblem` and `CliErrorCode` types. A command can throw `CliError` and return `data` for `--json`.
