# 0350: Prune ended workflow runs with workflows prune

- Status: accepted
- Date: 2026-11-08
- Amends: 0111, 0290

## Context

`better-supabase db prune-workflows` named an object (workflows) as a database
verb. ADR 0290 gives each command a `<group> <action>` shape, and a command
that works on the Workflow SDK's runs belongs to a group of its own.

## Decision

- The command is `better-supabase workflows prune`, in a new `workflows`
  group with its own docs page. Its flags and its consent rule are unchanged.
  `db prune-workflows` is gone and has no alias; running it is an unknown
  command.
- The Workflow SDK module's `pg_cron` hint names the new command.

## Not done

The other contract 3 flag renames of the naming plan (`--apply`, `--fix`,
`--write`, `--emit`, `--out-dir` and `--runExternalCode`), the block renames
`bulk` to `bulk-actions`, `rank` to `ratings` and `time-tracking` to
`time-entries`, the generated file layout and the config key renames are not
part of this change.

## Consequences

Scripts and cron entries that run `db prune-workflows` change to
`workflows prune`.
