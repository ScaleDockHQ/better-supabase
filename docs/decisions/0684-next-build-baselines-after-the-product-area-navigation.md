# 0684: Raise the next-build baselines after the product-area navigation and the list kit

- Status: accepted
- Date: 2026-11-11

## Context

Phase 0 of the example coverage plan groups the side navigation into twelve
collapsible product areas and moves the customers overview onto a read-only data
grid. Both add code, and `tests/next-build` fails when a route grows past its
baseline. The update script only lowers a baseline, so a raise is a hand edit with
the numbers in an ADR (ADR 0673, 0674, 0676).

## Decision

Raise the baselines to the measured numbers of a fresh `next build`.

| Baseline                               | Routes                    | Change                                                          |
| -------------------------------------- | ------------------------- | --------------------------------------------------------------- |
| First load (`baseline.json`)           | every route under `(app)` | median +4,969 B gzip: the Base UI collapsible of the navigation |
| First load                             | `/customers`              | +72,314 B gzip (429,088 to 501,402): the data grid and Select   |
| Server chunks (`server-baseline.json`) | 236 route entries         | median +196 B gzip, at most +1,727 B                            |
| Payload (`payload-baseline.json`)      | `en/customers.html`       | +39 B gzip, +289 B raw                                          |

The ReUI `Filters` chips load through `next/dynamic` with `ssr: false`. The same
build measured +185,416 B gzip for `/customers` with the chips in the first load
(429,088 to 614,504), so the lazy load keeps about 113 KB gzip out of the figure
above.

## Alternatives considered

Rendering every area open avoids the collapsible, but the menu then lists 80
entries on every page, which is the problem the areas solve. Loading the grid
on intent leaves the customers page without rows for the first paint, which the
instant navigation contract forbids.

## Consequences

Every later overview that moves onto the list kit adds the grid once; the second
page costs only its columns. The first phase 11 baseline reset records the
before and after numbers again. Revisit the navigation if the collapsible grows,
for example by replacing it with a `details` element.
