# 1248: Move to Workflow 5.8 and world-postgres 5.5 with rate limits off

- Status: accepted
- Date: 2026-11-25

## Context

`workflow` 5.8.0, `@workflow/world` 5.4.0 and `@workflow/world-postgres` 5.5.0
pass `minimumReleaseAge` on 2026-11-25. world-postgres 5.5.0 adds migration
0033, `workflow.workflow_rate_limits`, and declares `rateLimits` and
`rateEventsInBatch`. `@workflow/core` 5.8 reserves rate limit slots only for
spec 10 runs, and spec 10 needs `inBandFence`. The Supabase World mints spec 8
runs and declares `inBandFence: false` (ADR 1106), and it spreads the base
World's capabilities, so it would have claimed rate limits it never applies.

eve 1.5.0 bundles `@workflow/core` 5.8.0 and `@workflow/world` 5.4.0, the
protocol the World speaks, but it was published on 2026-11-25 00:43 UTC and
passes the release age a day later. eve 1.4.0 passes the release age and
bundles `@workflow/core` 5.7.0 and `@workflow/world` 5.3.0.

oRPC 2.0.0-beta.53 adds an `$InContext` type parameter to
`Builder.middleware`, which a generic `TContext` cannot satisfy through
inference.

## Decision

Pin `workflow` 5.8.0, `@workflow/world` 5.4.0, `@workflow/world-postgres`
5.5.0 and `eve` 1.5.0 in the default catalog, and raise the peer floors to
them with the ceilings kept (`@workflow/world >=5.4.0 <5.5`,
`@workflow/world-postgres >=5.5.0 <5.6`). `WORKFLOW_WORLD_PROTOCOL` and the
stub manifest move to 5.4.0.

`createSupabaseWorld` sets `rateLimits` and `rateEventsInBatch` to `false` next
to `maxConcurrency` and `inBandFence`. The World DDL is regenerated from
world-postgres 5.5.0, and the `workflow-sdk` module moves to version 10, whose
upgrade step creates the empty rate limit table through the regenerated module
(ADR 1100). The other catalog pins move to their latest releases that pass the
release age and stay within the current major, with each peer floor at its pin
(ADR 0848). eve 1.5.0 gets a maintainer-approved `minimumReleaseAgeExclude`
entry that is removed once it passes the release age on 2026-11-26. `rateLimit()` in `better-supabase/orpc` passes oRPC's generics and
annotates its options, so its public type is unchanged.

## Alternatives considered

Stay on eve 1.4.0 until 1.5.0 passes the release age. eve checks only the
major of the World's `@workflow/world` range, so 1.4.0 loads the 5.4 World,
but its bundled Workflow 5.7 core would run next to the World's 5.8 line.

Turn on rate limits. They need spec 10 runs and the in-band fence, which the
World does not implement (ADR 1106).

Skip the table. world-postgres 5.5 ships migration 0033, so the drift check
would fail at startup without it.

## Consequences

Apps run the version 10 upgrade before they deploy world-postgres 5.5.0, and
an app that stays on world-postgres 5.4 fails the drift check after it
upgrades better-supabase. Rate limits stay off until the World supports spec
10; that change flips the two capabilities and needs no new table.
