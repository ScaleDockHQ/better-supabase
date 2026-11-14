# 1023: Move to Workflow 5.5 and eve 1.0.0-rc.13 with six trust policy exclusions

- Status: accepted
- Date: 2026-11-14
- Amends: 1022

## Context

ADR 1022 kept `workflow` on 5.4.0 and eve on 1.0.0-rc.0 because the
releases both upgrades need dropped the provenance their earlier releases
had, and `trustPolicy: no-downgrade` rejects them until
`trustPolicyIgnoreAfter` (30 days) trusts them. Workflow 5.5.0 is the only
5.5 release, its `@workflow/core` depends on `@vercel/functions ^3.11.1`, and
every eve release candidate after rc.0 peers on `@vercel/connect ^2.7.0` and
bundles Workflow 5.5.

Each of those releases pins its dependencies exactly, so the chain has six
untrusted releases and no older version avoids any of them:

| Release                    | Reached through                      | Trusted after        |
| -------------------------- | ------------------------------------ | -------------------- |
| `@vercel/connect@2.7.0`    | eve's peer                           | 2026-11-30 00:48 UTC |
| `@vercel/oidc@4.0.5`       | pinned by `@vercel/connect` 2.7.0    | 2026-11-28 19:38 UTC |
| `@vercel/cli-config@0.3.5` | pinned by `@vercel/oidc` 4.0.5       | 2026-11-28 19:38 UTC |
| `@vercel/functions@3.11.1` | `@workflow/core` 5.5.0               | 2026-12-09 17:48 UTC |
| `@vercel/oidc@4.0.8`       | pinned by `@vercel/functions` 3.11.1 | 2026-12-09 17:48 UTC |
| `@vercel/cli-config@0.3.8` | pinned by `@vercel/oidc` 4.0.8       | 2026-12-09 17:48 UTC |

`@vercel/functions` 3.11.2 pins `@vercel/oidc` 4.0.9, a seventh untrusted
release. The maintainer approved exactly these six exclusions.

`@workflow/world` 5.2 adds `Queue.queueAuthMode`: a World that declares
`'loopback'` gets its flow-route deliveries checked against a shared queue
key, and one that declares `'skip'` is not checked. `@workflow/world-postgres`
5.2 declares `'skip'`, adds migration 0030 (`workflow_job_lock_holders`, the
workers that renew their Graphile job locks), and serves `events.subscribe`
for spec 9 runs from a `LISTEN` connection. Its capabilities, `inBandFence`
among them, are the same as in 5.1.

eve 1.0.0-rc.13 changes one type the adapter follows: `content.completed`
leaves out `runId` for a part its turn wrote without a model run. rc.6
requires a World with atomic start hooks, rc.11 passes dynamic schedules'
`auth` and `run` a `schedule` handle, lets `auth` return only
`{ attributes }`, and adds an optional collection `id`. `queueDynamicSchedules`
already passed the handle and accepted that result. No release candidate up
to rc.14 adds a public way for a custom `ScheduleProvider` to hand eve a timed
run, and none adds the `validateExpression` hook ADR 1022 expected.

## Decision

`pnpm-workspace.yaml` lists the six releases in `trustPolicyExclude`, each
with its trust date in a comment. `minimumReleaseAge` is unchanged and there
is no `minimumReleaseAgeExclude`: every release passes the one-day window.
The default catalog pins `workflow` 5.5.0, `@workflow/world` and
`@workflow/world-postgres` 5.2.0, `@workflow/world-testing` 5.1.0,
`@workflow/vitest` 5.0.9, `eve` 1.0.0-rc.13 (the newest candidate older than
`minimumReleaseAge` when it was set), `@vercel/connect` 2.7.0 and
`@vercel/functions` 3.11.1. The peers start there: `workflow >=5.5.0 <6`,
`@workflow/world` and `@workflow/world-postgres >=5.2.0 <5.3`,
`eve >=1.0.0-rc.13 <2`, `@vercel/connect >=2.7.0 <3` and
`@vercel/functions >=3.11.1 <4`.

The Supabase World speaks protocol 5.2.0 (`WORKFLOW_WORLD_PROTOCOL`). The
regenerated DDL adds `workflow.workflow_job_lock_holders`, and the
`workflow-sdk` SQL module moves to version 5 with that table under the same
row level security and service-role grants as the other World tables. The
World declares `queueAuthMode: "skip"` itself instead of inheriting it,
because its queue is the queue block, not world-postgres's: `createQueueHandler`
checks every delivery's HMAC signature before the runtime sees it. It keeps
the world-postgres capabilities, so `inBandFence` lets
`WORKFLOW_SPEC_VERSION=9` create spec 9 runs. The `@workflow/world-testing`
5.1 suite passes on the local stack; the queue key tests skip, as they do
for every `'skip'` World.

`persistSessions` types `content.completed`'s `runId` as optional; it keys
messages by `scope.turnId` and the part id, so nothing else changes.
`queueDynamicSchedules` keeps its design from ADR 1022, and its
`collections` are keyed by the collection name, which is the definition's
`id` when it sets one. No better-supabase extension interface changes, so no
`apiVersion` moves. The bundle and type baselines did not move.

## Alternatives considered

- Wait until 2026-12-09 17:48 UTC, when all six releases are trusted. The
  adapter and the World would stay a Workflow minor behind for another four
  weeks, and the maintainer chose the exclusions.
- Override `@vercel/oidc` or `@vercel/cli-config` to an older trusted
  release. Both packages would run against versions their dependents don't
  pin, which no test covers.
- Take eve rc.14, which adds fixed-schedule time zones and `endsTurn` for
  workflow tools and has the same dependencies. It was younger than
  `minimumReleaseAge` when the catalog was set; it is a catalog bump without
  new exclusions later.

## Consequences

Remove the exclusions as their dates pass: the three for `@vercel/connect`
2.7.0, `@vercel/oidc` 4.0.5 and `@vercel/cli-config` 0.3.5 after
2026-11-30 00:48 UTC, and the three for `@vercel/functions` 3.11.1,
`@vercel/oidc` 4.0.8 and `@vercel/cli-config` 0.3.8 after 2026-12-09 17:48
UTC. Each removal is a one-line change. The entries name exact versions,
so any other release in this chain that lacks provenance still fails the
install.

Apps apply the `workflow-sdk` version 5 migration before they deploy
`workflow` 5.5. Revisit the dynamic schedules firing path if eve publishes a
delivery entry point for custom providers, and add `validateExpression` to
`queueScheduleProvider` when eve's `ScheduleProvider` gains it.
