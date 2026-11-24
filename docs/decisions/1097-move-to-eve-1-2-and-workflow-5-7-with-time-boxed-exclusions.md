# 1097: Move to eve 1.2.0 and Workflow 5.7 with time-boxed release age and trust exclusions

- Status: accepted
- Date: 2026-11-20
- Amends: 1023

## Context

The eve on Supabase World work needs eve 1.2.0 (whose declared line is Workflow 5.7), `workflow` 5.7.0, `@workflow/world` 5.3.0 and
`@workflow/world-postgres` 5.4.0. All of them are younger than
`minimumReleaseAge` (1440 minutes), and The `ai` 7.0.178 and `@ai-sdk` releases that came with them are young too. Architecture invariant 14 says to pin the previous release instead.

The maintainer approved this one bump without waiting for the gates: a
narrowly scoped `minimumReleaseAgeExclude`, exact `package@version` entries
only, and the `trustPolicyExclude` entries the install needs. This ADR is a
maintainer-approved, time-boxed deviation from invariant 14, not a change of
the rule.

## Decision

`pnpm-workspace.yaml` lists the releases below in `minimumReleaseAgeExclude`
(no wildcards, `minimumReleaseAge` unchanged), in two blocks with a comment
that names the removal date, and the entries below in `trustPolicyExclude`
with their trust dates.

The release age exclusions for the Workflow 5.7 packages, `@vercel/connect@2.9.5`
and `@vercel/drives@1.0.0` (published 2026-11-19, the newest at 20:40 UTC) were
removed on 2026-11-20 after 20:41 UTC, when each passed `minimumReleaseAge`.
`pnpm view <package>@<version> time` showed each release between 20:34 and
20:41 UTC on 2026-11-19.

Release age exclusions that remain, published 2026-11-20, removable after
2026-11-21 16:53 UTC (`eve@1.2.0` after 15:55 UTC):

`eve@1.2.0`, `ai@7.0.178`, `@ai-sdk/anthropic@4.0.107`,
`@ai-sdk/gateway@4.0.151`, `@ai-sdk/harness@1.0.189`, `@ai-sdk/mcp@2.0.102`,
`@ai-sdk/provider-utils@5.0.83`, `@ai-sdk/react@4.0.182`,
`@ai-sdk/sandbox-vercel@1.0.189`, `@ai-sdk/workflow@2.0.110`,
`flags@4.5.0`, `@vercel/sandbox@4.1.0` and `@vercel/sdk@1.28.67`.

Trust policy exclusions (`no-downgrade` rejects releases that lost the
provenance of earlier ones until `trustPolicyIgnoreAfter`, 30 days, trusts
them):

| Release                    | Reached through                      | Trusted after        |
| -------------------------- | ------------------------------------ | -------------------- |
| `@vercel/connect@2.9.5`    | eve 1.2.0's peer                     | 2026-12-19 20:39 UTC |
| `@vercel/functions@3.11.3` | `@workflow/core` 5.7.0               | 2026-12-13 23:55 UTC |
| `@vercel/oidc@4.0.9`       | pinned by `@vercel/functions` 3.11.3 | 2026-12-12 15:58 UTC |
| `@vercel/cli-config@0.4.0` | pinned by `@vercel/oidc` 4.0.9       | 2026-12-12 16:00 UTC |

The three entries from ADR 1023 (`@vercel/functions@3.11.1`,
`@vercel/oidc@4.0.8`, `@vercel/cli-config@0.3.8`) stay until their trust date,
2026-12-09 17:48 UTC. The entries for `@vercel/connect@2.7.0`,
`@vercel/oidc@4.0.5` and `@vercel/cli-config@0.3.5` are gone, because nothing
resolves those releases any more.

The default catalog pins `eve` 1.2.0, `workflow` 5.7.0, `@workflow/world`
5.3.0, `@workflow/world-postgres` 5.4.0, `@workflow/world-testing` 5.1.3,
`@workflow/vitest` 5.0.12, `ai` 7.0.178, `@ai-sdk/*`, `chat` and
`@chat-adapter/*` 4.45.0, `flags` 4.5.0, `@vercel/sandbox` 4.1.0,
`@vercel/connect` 2.9.5, `@vercel/functions` 3.11.3, `@vercel/kms` 0.3.12,
`@vercel/sdk` 1.28.67 and `@vercel/detect-agent` 1.2.7. The peer floors start
at the same releases: `eve >=1.2.0 <2`, `workflow >=5.7.0 <6`,
`@workflow/world >=5.3.0 <5.4` and `@workflow/world-postgres >=5.4.0 <5.5`.
`@vercel/queue` stays on 0.11.0, its newest release.

Supported eve versions: eve 1.2.0 and later in the 1.x line, with Workflow
5.7. Earlier eve releases are not supported.

The Supabase World speaks protocol 5.3.0 (`WORKFLOW_WORLD_PROTOCOL`). The
regenerated DDL adds `workflow.workflow_run_delivery_leases` (migration 0031)
and `workflow_runs.wake_pending` (migration 0032). The `workflow-sdk` SQL
module moves to version 6. Its upgrade step adds `wake_pending` with a
default of `true`, so runs that exist before the upgrade start with the flag
set and startup recovery lets their next completed delivery decide, then
changes the default to `false`, as world-postgres does. The module's file
adds the column with the final default, which would clear existing rows, so
the step has to run first. `better-supabase/workflow-sdk/world/package.json`
is a stub manifest that carries the `@workflow/world` range, so eve's startup
check compares its Workflow line with the World's.

No structural type in `better-supabase/eve` changes from eve 1.0.0-rc.13 to
1.2.0, so no extension interface moves its `apiVersion`.

## Alternatives considered

- Wait until 2026-11-21 16:53 UTC, when every release is old enough. The
  work that follows needs the new line today, and the maintainer chose to go
  ahead.
- Pin the previous releases (`workflow` 5.5.0, eve 1.0.0-rc.13). That is what
  invariant 14 says, but the World, delivery and projection work targets
  protocol 5.3.0 and eve 1.2.0, so the previous releases would be a second
  round of changes.
- Lower `minimumReleaseAge` or exclude by wildcard. Both widen the exception
  to releases nobody reviewed.

## Consequences

Follow-up (delete the exclusions after their dates):

- After 2026-11-21 16:53 UTC delete the remaining `minimumReleaseAgeExclude`
  block (`eve@1.2.0` passes at 15:55 UTC). `minimumReleaseAgeExcludePrune`
  removes an entry once its release passes the window, so the file may already
  have lost entries; delete what is left and the `minimumReleaseAgeExclude`
  key itself.
- Delete the `trustPolicyExclude` entries on their dates: 2026-12-09 17:48 UTC
  (ADR 1023's three), 2026-12-12 15:58 and 16:00 UTC, 2026-12-13 23:55 UTC
  and 2026-12-19 20:39 UTC.
- Delete the notes on invariant 14 in `AGENTS.md` and
  `.agents/rules/architecture.mdc` once the last block is gone.

Until then the lockfile holds releases that are younger than the policy
allows. Every one is exact, so any other too-young release still fails the
install. Apps apply the `workflow-sdk` migrations (versions 6 to 8, ADR 1100) before they
deploy `workflow` 5.7.

## Closure

The time box ended on 2026-11-21. The `minimumReleaseAgeExclude` entries were removed on 2026-11-24 and every release passes `minimumReleaseAge` on its own.
