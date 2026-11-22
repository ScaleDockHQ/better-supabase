# 1105: Move to eve 1.3.0 and Workflow 5.7.1 with time-boxed release age exclusions

- Status: accepted
- Date: 2026-11-21
- Amends: 1097

## Context

eve 1.3.0 bundles `workflow` 5.7.1, and `@workflow/world-postgres` 5.4.1
changes what the World writes when a zero-retention run ends: the terminal
transaction adds a purge backstop job through Graphile Worker's `add_job`.
`ai` 7.0.179 and its `@ai-sdk` packages came out the same evening. All of
them were published on 2026-11-20 between 20:37 and 23:29 UTC, so they are
younger than `minimumReleaseAge` (1440 minutes). Architecture invariant 14
says to pin the previous release instead.

The maintainer approved moving to the new line now, on the same terms as
ADR 1097: exact `package@version` entries in `minimumReleaseAgeExclude`, no
wildcards, `minimumReleaseAge` unchanged, and a removal date on each block.
This ADR is a maintainer-approved, time-boxed deviation from invariant 14,
not a change of the rule.

## Decision

`pnpm-workspace.yaml` adds one `minimumReleaseAgeExclude` block, removable
after 2026-11-21 23:29 UTC. `pnpm view <package> time` gives the publish
times; the Workflow entries pass the window by 20:44 UTC, `eve@1.3.0`
(published 23:26 UTC) by 23:26 UTC and `@ai-sdk/react@4.0.183`, the newest,
at 23:28 UTC:

`eve@1.3.0`, `workflow@5.7.1`, `@workflow/core@5.7.1`,
`@workflow/world-postgres@5.4.1`, `@workflow/world-testing@5.1.4`,
`@workflow/vitest@5.0.13`, `@workflow/world-local@5.5.1`,
`@workflow/world-vercel@5.7.1`, `@workflow/errors@5.1.5`,
`@workflow/builders@5.1.4`, `@workflow/cli@5.3.1`, `@workflow/web@5.3.1`,
`@workflow/next@5.1.4`, `@workflow/nest@5.1.11`, `@workflow/astro@5.0.13`,
`@workflow/nitro@5.0.13`, `@workflow/nuxt@5.0.13`, `@workflow/rollup@5.0.13`,
`@workflow/sveltekit@5.0.13`, `@workflow/vite@5.0.13`, `ai@7.0.179`,
`@ai-sdk/gateway@4.0.152`, `@ai-sdk/harness@1.0.190`,
`@ai-sdk/react@4.0.183`, `@ai-sdk/sandbox-vercel@1.0.190` and
`@ai-sdk/workflow@2.0.111`.

The install needs no new `trustPolicyExclude` entry. The entries ADR 1097
excluded (`ai@7.0.178`, `eve@1.2.0` and the `@ai-sdk` releases 7.0.179
replaces) are gone, because nothing resolves them any more; the rest of its
block stays until 2026-11-21 16:53 UTC.

The default catalog pins `eve` 1.3.0, `workflow` 5.7.1,
`@workflow/world-postgres` 5.4.1, `@workflow/world-testing` 5.1.4,
`@workflow/vitest` 5.0.13, `ai` 7.0.179, `@ai-sdk/react` 4.0.183,
`@ai-sdk/sandbox-vercel` 1.0.190 and `@ai-sdk/workflow` 2.0.111.
`@workflow/world` stays on 5.3.0, so `WORKFLOW_WORLD_PROTOCOL` stays 5.3.0
and the stub manifest keeps its range. The peer floors move to
`eve >=1.3.0 <2`, `workflow >=5.7.1 <6`, `ai >=7.0.179 <8` and
`@workflow/world-postgres >=5.4.1 <5.5`. eve 1.3.0 adds `eve/solid` with an
optional `solid-js` 2 peer. better-supabase never loads `eve/solid`, so an
`allowedVersions` rule (`eve>solid-js`) accepts the repo's Solid 1.9.19 for
that peer instead of failing `strictPeerDependencies`. Chat SDK 4.45.0, Flags SDK 4.5.0 and every `@vercel/*` pin are already
the newest releases.

world-postgres 5.4.1 adds no migration, so the regenerated DDL changes only
its version. Its purge backstop calls
`<GRAPHILE_WORKER_SCHEMA>.add_job(...)`, and this World runs no Graphile
Worker. The World sets `GRAPHILE_WORKER_SCHEMA` to `workflow` when the app
leaves it unset, and the `workflow-sdk` SQL module (version 9) adds
`workflow.add_job`, which records only the purge task in
`workflow.workflow_purge_backstops` and rejects any other task with
`WORKFLOW_GRAPHILE_UNSUPPORTED`. `workflow_purge_backstops()` clears the data
of due runs whose purge did not finish. The World runs it while it polls,
and the `pg_net` and `vercel-queue` modes schedule it every minute under
pg_cron. world-postgres's `skipWorkers` option is exposed as the World's
`skipWorkers` and `WORKFLOW_POSTGRES_SKIP_WORKERS=1`.

eve 1.3.0's custom-skills scope context gains `turn` and `session.parent`.
`better-supabase/eve` adds `supabaseSkillScopes()`, a structural resolver
for that context, and imports nothing from eve at runtime. No existing
extension interface changes, so no `apiVersion` moves.

## Alternatives considered

- Wait until 2026-11-21 23:29 UTC. The maintainer chose to move now and
  delete the block after that time.
- Stay on `@workflow/world-postgres` 5.4.0 with eve 1.3.0. eve 1.3.0 bundles
  `workflow` 5.7.1, and its zero-retention runs then depend on a purge path
  the older World does not have.
- Point `GRAPHILE_WORKER_SCHEMA` at a real Graphile Worker schema. That
  installs and runs a second queue next to the one the World already uses.
- Lower `minimumReleaseAge` or exclude by wildcard. Both widen the exception
  to releases nobody reviewed.

## Consequences

Follow-up (delete the exclusions after their dates):

- After 2026-11-21 16:53 UTC delete ADR 1097's remaining block.
- After 2026-11-21 23:29 UTC delete this ADR's block, then the
  `minimumReleaseAgeExclude` key once it is empty.
- Delete the notes on invariant 14 in `AGENTS.md` and
  `.agents/rules/architecture.mdc` once the last block is gone.

Apps apply the `workflow-sdk` version 9 migration before they deploy
`@workflow/world-postgres` 5.4.1. An app that sets `GRAPHILE_WORKER_SCHEMA`
to another schema gets a warning at startup, and its purge backstops go
there instead.
