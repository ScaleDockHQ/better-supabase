# 0605: Write each renamed block to its own module, and measure before making blocks lazy

- Status: accepted
- Date: 2026-11-10
- Amends: 0232, 0542

## Context

47 of the Next.js example's 48 generated records imported `blocks.generated.ts`, which has 280
static block imports, because `tasks` renames its entities and a renamed block was only exported
from there. ADR 0262 and the plan assumed the block config would have to import the block back;
it doesn't: `blockConfig` lives in `blocks.config.ts`, which imports no block.

## Decision

With `gen.blockModules`, each instance that renames a block's entities writes
`blocks/<instance>-block.ts`: the block under its renamed constant plus its renamed types, built
from `blocks.config.ts`. `blocks.generated.ts` re-exports them (`export *`) and imports only the
names it uses. A record imports its blocks from those modules, and from `blocks.generated.ts`
never (a generator test checks it). A multi-instance block's module imports only the `Default*`
names its own renames reach.

## Measurement for the lazy-block decision

From `tests/next-build/server-baseline.json` after the change (gzip, `(app)` page routes, 111
of them): floor 519 KB (`forbidden`), median 853 KB, maximum 1,446 KB; `customers` 527 KB,
`notifications` 520 KB, `settings/audit` 523 KB. The 330 KB between floor and median is route
code in total, not the block set alone: I did not compare one route on the full set against the
same route on the shell set with the analyzer, so the 100 KB condition of the plan is not shown to
hold. Client first-load gzip fell by about 0.7 KB on every route (the records no longer pull
`blocks.generated.ts` in the browser build). Lazy block loaders are not started.

## Consequences

The next step for lazy blocks is the analyzer comparison on one median route. Until then the
named block sets of ADR 0542 remain the way to cut a route's blocks.
