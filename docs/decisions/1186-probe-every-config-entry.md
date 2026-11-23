# 1186: The prune probe tries every entry a render can answer

- Status: accepted
- Date: 2026-11-22

## Context

`codemod config --prune` and doctor (BS427) found two kinds of entries that
equal a default: the structural ones in `restatedEntries` and the `permissions`
and `options` entries a render without them leaves byte-equal (ADR 1174).
CentraKit still held `callbacks` entries that name the function the block looks
up anyway, `api` entries and `on` entries the schema's foreign keys give.

## Decision

The probe takes the same test to more of the block entry. A candidate is a leaf
of `permissions`, `options`, `callbacks`, `tables`, `columns` or `api`, a
`links`, `column` or `table` key of `on`, or an `idType`, `table` or `cascade` of
a record type. A config file writes `callbacks` where the resolved entry says
`hooks`, so the path uses the file's key.

Three limits keep the cost down. A `tables`, `columns` or hook entry is tried
only when it keeps the default name (the `plausible` check). An `api` entry the
project's `sql.api` filled in is not tried, because it is not in the file.
Options nested deeper than three keys are data, not defaults. The entries most
likely to match go first, and the probe stops after 400 renders.

`database` entries stay out of the probe: the resolved `sql` holds defaults
that a patched copy cannot tell from written values.

## Consequences

- CentraKit goes from 3329 to 3295 lines (17 `callbacks` lines, 17 `api`
  lines). The 2500 target is not met.
- A render costs about two seconds on CentraKit, so a full run of the codemod
  takes minutes longer. Run it again to try the entries the cap skipped.
- Each new kind of entry is a new `RestatedKind`.

## Alternatives considered

- Probe every leaf. Over 1300 candidates at two seconds a render is too slow.
- Patch `database` through the config file. It would need a render per key from
  the file, which `renderUnchanged` already does for the groups that remain.
