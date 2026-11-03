# 0210: Move the Supabase World to @workflow/world-postgres 5.1

- Status: accepted
- Date: 2026-11-03

## Context

`@workflow/world-postgres` 5.1.0 changes the World tables (timestamps become
`timestamptz`, runs get a job prefix and claim token, hook admissions and
`start_hook_cbor` appear) and the protocol (spec version 8, in-band fence).
The Supabase World keeps its own queue, so it follows the table shape and the
`@workflow/world` contract, not the graphile worker.

## Decision

- The catalog pins `@workflow/world` and `@workflow/world-postgres` at 5.1.0.
  The peer ranges are `>=5.1.0 <5.2`. `WORKFLOW_WORLD_PROTOCOL` is 5.1.0.
- `scripts/gen-workflow-ddl.ts` regenerates the DDL from the installed
  migrations (now 0027 to 0029). The `workflow-sdk` SQL module is version 4:
  it converts existing World timestamps to `timestamptz` and drops the
  `at time zone 'UTC'` casts. `assertWorldMigrations()` compares the
  installed migration hashes at `start()` and throws `MigrationDrift`.
- `createWorld()` returns one World per process. `onDeadLetter`,
  `enableInvoke` and `streamFlushIntervalMs` are options, the delivery
  headers match world-postgres, `queueBatch` is one statement, and the World
  warns about a transaction pooler.
- `openHooks()` decodes `metadata_cbor` with the run key and falls back to
  the `metadata` column. Payloads sealed for another recipient stay closed.
- The Database workflow runs the `@workflow/world-testing` suite against the
  stack and uploads the report.
- `@workflow/world-testing` and `@workflow/vitest` stay at 5.0.6. The 5.1
  testing release needs `@workflow/core` releases that were also inside the
  window.

## Exception to the release age policy (AGENTS.md rule 14)

The repo owner allowed this bump before the 1440 minute `minimumReleaseAge`
window closed. This overrides rule 14 for this change only. `pnpm-workspace.yaml`
lists four exact releases in `minimumReleaseAgeExclude`: `@workflow/world@5.1.0`,
`@workflow/world-postgres@5.1.0`, `@workflow/world-local@5.2.0` and
`@workflow/errors@5.1.0` (the last two are strictly required transitive
dependencies). The global `minimumReleaseAge` is unchanged.

All four were published on 2026-11-02 between 22:44 and 22:45 UTC. `pnpm view`
shows trusted-publisher (OIDC) publication with SLSA provenance
attestations and the same maintainers as earlier releases; nothing odd was
found. Remove the list on or after 2026-11-03 22:46 UTC, when the releases
are old enough and the entries are redundant.

## Consequences

- Apply the `workflow-sdk` module upgrade before deploying the app. Runs
  started under protocol 5.0 finish; new runs use spec version 8.
- Peer versions below 5.1.0 are no longer supported.
