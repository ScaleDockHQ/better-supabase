# 0440: Seeds are a declarative data layer

- Status: accepted
- Date: 2026-11-08
- Amends: 0205, 0254

## Context

ADR 0205 left system rows "in the module's own SQL", and ADR 0254 moved the
other rows into per-module data files. Two things were still wrong for a
declarative workflow. The `membership_roles` backfill was a top-level `insert`
in the memberships schema file, which a schema diff never applies and doctor
BS374 reports. The data migration wrote every data statement each time, so a
block upgrade repeated all rows and nothing showed which statement was new.

## Decision

Data files are the desired state of block rows. They hold keyed upserts (`on
conflict (...)` or `not exists`) and calls to `seed_<module>_defaults(tenant,
variant, locale)`; the function definitions stay in the module. The
memberships module hands the `membership_roles` backfill to its `data` field,
with the table's primary key as the conflict target.

`add --adopt` splits the data files into statements and compares them, without
comments and extra whitespace, with the statements of every data migration
already in the migrations folder. It writes one content-stamped migration with
only the missing statements, grouped by module, after a `lock_timeout`. With
nothing missing it writes nothing. `--check` and `upgrade --check` exit with 1
when a statement is missing.

Doctor reads the data files: BS357 reports an insert without a key, BS358 an
app seed (`supabase/seeds`) that writes a table a block data file writes, and
BS359 a `seed_*_defaults` function without a locale. App seed files stay the
app's; `upgrade` never writes rows into them.

## Alternatives considered

Keeping the all-statements migration needs no diff, but each upgrade repeats
every row and hides the change. Tracking applied statements in a table would
need a runtime dependency on the database for a file comparison.

## Consequences

A changed statement, such as a new block version in the `blocks` row, is
written once. A statement removed from a data file is never undone, because a
migration only adds rows. Reference data such as tax codes stays a locale
migration the app opts into.
