---
"better-supabase": minor
---

A faster CLI that reads the database less often.

- `--help` and each command's `--help` start in about 30 to 50 ms instead of
  130 to 150 ms: the commands, config loading, env validation, prompts and
  the typegen schemas load only when a command runs.
- `gen` hashes the system catalogs with one query and reuses the snapshot
  cached in `node_modules/.cache/better-supabase` while the schema is
  unchanged. `gen --watch` keeps one connection open and polls that hash, so
  an unchanged schema costs one small query per interval.
- Introspection runs its queries concurrently over a pool of four
  connections. Connecting gives up after 10 seconds and each introspection
  query after 2 minutes; Ctrl-C ends the connection or Management API request
  and exits with code 130.
- `doctor` reads the snapshot and runs its live checks and splinter over one
  connection, and reads its input files concurrently.
- `oxfmt` is now an optional peer. Without it, `gen` writes
  `database.types.ts` unformatted and prints a notice instead of failing.
- Generated files and doctor reports sort names by code point, so they no
  longer depend on the machine's locale. Run `better-supabase gen` once; the
  order of a few entries in `generated.ts` and the validator files can change.
- Breaking: `parseSnapshot` from `better-supabase/cli` now returns a promise,
  so the typegen schemas load on first use. Add `await`. `loadSnapshot` takes
  `signal` and `cache` in its source options.
