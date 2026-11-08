# 0381: One confirm flag and one out flag

- Status: accepted
- Date: 2026-11-08
- Amends: 0045, 0290

## Context

Contract 3 (ADR 0290) says `--yes` confirms and `--out <path>` names a file
output. Five flags still said the same thing another way: `db seed --apply`,
`doctor --fix`, `dev env --write`, `gen --emit` and `gen --out-dir`.

## Decision

- `db seed --apply` and `doctor --fix` are `--yes`: the command that has a
  database side effect only runs it with `--yes`. `--dry-run` and `--check`
  still preview, and the consent metadata in `manifest.ts` names `--yes`.
- `dev env --write <file>` is `--out <file>` (`-` still prints).
- `gen --out-dir <dir>` is `--out <dir>` with `--metadata`. `gen --emit <file>`
  is `--only <file>` with `--metadata`, since `--only` already picks what
  `gen` produces.
- Each old flag is in `REMOVED` and exits 2 with `flag_renamed` and the new
  command line. There is no alias.
- `--runExternalCode` is a `tsc` flag the content mapper passes through, so it
  stays. `pnpm supabase:prune --apply` is a repo script, not the CLI.

## Consequences

A script that passes an old flag fails with the replacement in the message.
`doctor --yes` runs fixes, so do not add `--yes` to a read-only doctor run.
