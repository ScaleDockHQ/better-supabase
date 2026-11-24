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

## Measurements and follow-ups

The measured run is the final build as the admin and the member at the seed tier,
and as the admin at tier L (`pnpm db:seed:scale --tier l`: 1.1M notes, 1M audit
events and 1M notification recipients). The median cold render of 237 routes is
155 ms at the seed tier and 157 ms at tier L, so volume does not move the typical
page. The follow-ups below are ranked and none is tuned in this change.

1. `/care/[clientId]` (1407 ms cold, 21 calls) and `/funding` (1056 ms cold, 931 ms
   warm): the slowest pages and the chattiest page; the dossier and the funding
   overview read several blocks in one island.
2. The approvals badge in the shell adds one `page_approvals()` call to every cold
   route, which is why 22 `maxCalls` budgets rose by one. Move the badge count into
   the bootstrap read.
3. `/crm/deals` (16 calls), `/inbox/[conversation]` (16), `/people/leave` (13),
   `/finance/invoices/[id]` (13) and `/customers/[id]` (13): islands with more than
   one read each; merge the reads behind one composite.
4. Tier L grows `/assistant/usage` by 103 ms, `/assistant/agents` by 57 ms and
   `/finance/recurring` by 46 ms: the only routes where volume shows.
5. `/settings/security` (688 ms) and `/medications` (552 ms) are slow at both tiers.
6. Auth cost: `tests/bench-scopes.spec.ts` counts up to 3 token verifications on a
   cold remote cache where it expects 1; check the verification cache key.
7. 23 detail routes of the manifest have no `h1` for the seeded id (the measure
   spec skips their heading check), and `/workflows/builder` reads `builder` as a
   definition id. Give each a heading or a not-found page.
8. `publishWithVersion` needs a versions subject over public tables, and
   `support.openTicket` hardcodes the `task` subject while this app names the
   entity `work_item`. The sample works around both; see
   `tmp/findings/sample-depth-findings.md`.

### Baseline raise for the full sample

The full sample adds the record kit, the area routes and the shared navigation to every
page. The next-build baselines moved on purpose: the server chunks of every route grew by
about 0.6 MB raw (3.2 MB to 3.8 MB) because the config now carries the descriptors of all
13 areas, and the first-load JavaScript of the finance and banking record pages grew by up
to 9 percent. A follow-up should split those descriptors per area so a route loads only
its own.

Later in the same change, the record sections for conversations and workflow
progress and the live refresh on the timeline raised the first-load and server
baselines again; both files were rewritten from the final build.
