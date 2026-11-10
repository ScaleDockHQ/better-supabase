# 0632: Measure a 1,200 table profile in the type bench

- Status: accepted
- Date: 2026-11-10

## Context

ADR 0591 found that the `centrakit` profile (250 tables) checks at about 28,000 types with ts7,
where the real app checks at 346,000 to 405,000, and that the content mapper costs 4.3 times the
instantiations on the composite profile.

## Decision

`tests/types/perf` gets a `real` profile of 1,200 tables and 240 queried tables with the
composite shape. It is gated like the others. Measured with ts7: 126,289 types and 252,028
instantiations, check 0.28 s; with the ts7.1 mapper 1,047,493 instantiations, 4.2 times the plain
run. The `centrakit` profile shows 215,805 against 50,139, 4.3 times. The ratio holds from 250 to
1,200 tables, so the mapper cost is per type and not a quadratic effect of the schema size.

## Not done

The cause of the 4.3 times is not found. A real-size profile needs about 3,000 tables to reach
CentraKit's type count, which the bench would take several minutes to build.
