# 0860: Generate list indexes and a scale plan check

- Status: accepted
- Date: 2026-11-14

## Context

The example's lists were indexed by hand after `EXPLAIN` at tier L found four
missing indexes (ADR 0685, EX-012, EX-015). Doctor checked a searched table
(BS392) and a list cursor in SQL (BS628), but not whether the sorts, facets and
search an entity's page declares have an index (EX-1270). The scale folder has
23 pgTAP files and none per list (EX-1265, EX-014, EX-410, EX-607, EX-1001).

## Decision

`gen.entityPages` writes one migration, `<stamp>_better_supabase_entity_page_indexes.sql`,
through the same managed-migration list as the permission catalog: a later run
replaces it whole, and `gen --check` reports it stale. For each page it writes
`create index if not exists` for every declared sort (`(tenant, column, id)`),
every facet (`(tenant, column)`) and every searched column named in the
manifest (`gin (column extensions.gin_trgm_ops)`). A name maps to a column only
when it is a logical column of the entity's table spec, in the manifest's name
or its snake case; a derived sort, or a facet over a join (`band` on risks), has
no index. `search: true` has none, because the block's own search column covers
it.

Doctor adds BS636. It runs the same resolution and reports each wanted index
that no btree index leading with the column (after the tenant column) or GIN
index on the column satisfies. It needs a snapshot with the table, so it stays
silent without one.

`scale_list_<name>.test.sql` is a pgTAP file in `gen.entityPages.scaleDir`
(`supabase/tests/scale`, or a folder outside the project, which `gen` now writes
from its own directory as it does for read sets). With sequential scans off it
plans each sort, which must have no sort step, and each facet count, which must
be an index-only scan. It inserts no rows: block tables have required columns,
foreign keys and triggers that a generic insert cannot satisfy, so it reads what
the stack holds and `db:seed:scale` supplies the volume.

On the local stack, before the migration the risks and periods files failed on
the sorts and facets without an index, and after it all 9 assertions passed.

## Alternatives considered

- Insert generated rows into the block table. It would fail on every block with
  a constraint the generator does not know.
- Check the SQL files instead of the snapshot (as BS628 does). The block tables
  come from generated modules, so the live shape is what the page reads.
- Index every manifest name by guessing the column. A wrong guess writes a
  failing migration, so unmapped names are left out and visible in the output.

## Consequences

A new page comes with its indexes and a failing test when one is missing. The
index set is derived, so removing a sort from a manifest leaves the old index in
place (the migration only adds). Tier-L timings still come from the scale seed
and `example:perf-report`; this file holds the plan shape, as ADR 0424 intended.
