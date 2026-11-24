# 1229: Measure the Next.js example with a committed harness

- Status: accepted
- Date: 2026-11-24

## Context

The Next.js example has more than 200 routes and 470 Server Actions, and its
numbers (database calls, waves, token verifications, cold and warm time,
first-load JavaScript) were taken by hand when somebody asked. Pages and
actions changed without a before and after.

## Decision

The example carries a harness in `apps/examples/nextjs/tests` that runs against
the production build with `EXPOSE_TESTING_API=1`: `resolve-urls`, `cold-warm`,
`measure-pages` (admin and member), `budgets`, `actions`, `auth-cost` and
`instant-routes`. `node scripts/example-perf-report.ts --write` turns the run
into `apps/examples/nextjs/perf/report.json` and `docs/agents/example-perf.md`.
The run is taken at the seed tier; tier L (`pnpm db:seed:scale`) is a separate
run that has not been recorded yet.

`pnpm check:example-generated` lists the generated modules the app and its
tests import, and fails when more are unused than
`perf/generated-coverage.json` allows. `src/features/areas/areas.ts` groups
the 54 presets into 13 product areas, and `pnpm check:example-coverage` checks
the grouping and the routes it names. `tests/features/architecture-guards.test.ts`
ratchets the prefetch, `fallback={null}` and client skeleton counts.

Numbers are recorded, not tuned. A page that is slow or chatty goes on the
follow-up list instead of being fixed in the same change.

## Alternatives considered

- Keep taking numbers by hand. Rejected: nothing makes a regression visible.
- Run the harness in CI. Rejected for now: it needs the full local stack and
  about an hour; the report is committed instead.

## Consequences

A change to a page can be compared with the committed report. Wall times vary
by up to 40% between runs on a shared VM, so only call counts and waves are
trusted for comparison. Revisit when the harness runs in CI or tier L is
recorded.
