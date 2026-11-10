# 0661: Render rpc, stored rollup and copy functions from tags

- Status: accepted
- Date: 2026-11-10
- Amends: 0637

## Context

ADR 0637 rendered `access`, `list` and `idempotency` from `@bsb` tags and listed `rpc`, `rollup stored`
and `copy` as not done. CentraKit writes the same three shapes by hand: a function that loads rows by
a list of ids, a trigger that keeps a count on a parent row, and a function that duplicates a row.

## Decision

`rpc`, `rollup` and `copy` join the rendered features. `table enable <tag>` writes each between marker
comments in the table's file, as the others do.

- **rpc** renders `get_<table>_by_ids(ids)`: `security invoker`, rows in the order of the ids, at most
  `max` ids (default 500, up to 5000). Row security decides the rows. It is the id source for a list
  that loads its rows by id.
- **rollup stored** renders a trigger function and trigger that keep a parent column equal to the
  count, or the sum of a child column, of the child rows. The function is `security definer` with an
  empty search path and no execute grant, because the child's writer may not be allowed to write the
  parent. A row that moves to another parent leaves the old total and joins the new one. One rollup per
  child table, and only the stored form: the tag must read `rollup stored`.
- **copy** renders `copy_<table>(source)`: `security invoker`, inserting the listed `columns` with
  optional text suffixes and returning the new row. Row security decides what is read and inserted. The
  columns are explicit, so a renderer that reads no catalog never copies a generated column.

The rendered text is checked twice: a pgTAP file applies the blocks to real tables and calls them, and
a unit test compares the file's text with the renderer's output.

## Alternatives considered

- Read the catalog to choose the copied columns: tags render without a database today, and a catalog
  read would make `table enable` depend on a running stack.
- A computed rollup view: ADR 0044 already renders those for app tables from config.
- Backfill inside the block: schema files hold declarative statements, and a one-off update does not
  belong in them. The docs point to `db backfill`.

## Consequences

Apps drop three hand-written shapes. The rollup trigger adds one parent update per child write, so a
hot parent row serialises its children's writes; a very hot counter wants a different design.

Seven First Load JS and server brotli baselines in `tests/next-build` rose by 7 to 51 bytes (under
0.01 percent of a route); brotli moves with chunk hashes, and the numbers are re-measured from a
fresh build of this branch after merging main. The guard in `next-build.test.ts` is unchanged.
