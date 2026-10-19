---
"better-supabase": minor
---

The CLI reports every failure with an error code and a matching exit code. The errors page lists each code, and `--json` puts it in `code`.

- Exit code 3 means you have to act first, 130 means a cancelled prompt or Ctrl-C, and 143 means SIGTERM. A cancelled prompt no longer counts as "no".
- A path flag outside the project root (`outside_root`) exits 2, like other usage errors, instead of 1.
- `--cwd` has to name an existing directory.
- `--db-url-stdin` and `gen --metadata -` fail at once when stdin is a terminal, instead of waiting for input.
- `$CI=false` and `$CI=0` no longer turn prompts off.
- The CLI never downloads the Supabase CLI through `npx --yes`. It runs `$SUPABASE_BIN`, then `node_modules/.bin/supabase`, then `supabase` on the `PATH`, and fails with `supabase_cli_missing` otherwise. The child process gets the run's environment and stops on Ctrl-C.
- Install commands quote version ranges and directories that the shell would split or expand.
- `tsconfig.json` and `package.json` are read as JSONC, so comments inside strings and trailing commas parse correctly.
- The config file is discovered once per run, and the local stack's database URL is looked up once.
- The package no longer ships `dist/cli/bin.d.ts`.
