# 0770: Raise the bundle and server baselines for the G3 list surface

- Status: accepted
- Date: 2026-11-14

## Context

The commerce list surface (ADR 0769) adds the sort, facet and filter declarations
and the page, facets and count methods to seven block entries. Their gzip sizes
grow past the baseline in `tests/bundle/baseline.json`, as the G5 entries did
(ADR 0790), and so does the example app's server chunk size.

## Decision

Raise the seven entries (commissions, donations, leases, manufacturing, periods,
referrals and shipments) to the sizes the CI bundle job measured. Each grows by
about 2.5 to 3 kB gzip. The shared `entityList` code is already in the core, so
the growth is the per-block declarations and methods.

Raise the 264 route entries in `tests/next-build/server-baseline.json` that the
next-build job reports as grown, to the measured values. Every route loads the
block set, so each grows by about 3 kB raw.

## Consequences

The baseline keeps catching unplanned growth. A later lane that adds more
entities to these blocks raises the same entries again, with its own ADR.
