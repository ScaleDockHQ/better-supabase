# 0256: Read app columns as fields and move extraColumns into app files

- Status: accepted
- Date: 2026-11-07
- Amends: 0250

## Context

`blocks.<name>.options.extraColumns` and about 45 prefixed options added a
column to a block's table from the config: the block emitted `alter table add
column if not exists`, so the column lived in a config object and in a module
file that `upgrade` rewrites, and an app that declared the same column in its
own schema file declared it twice.

## Decision

An app file owns its columns. `parseDeclared` records the type text of each
`alter table ... add column` (`AlteredTable.definitions`) and `appColumnsOf`
collects the ones that files without a `@bsb-block` line add, by `schema.table`.
`upgrade` passes them as `layout.appColumns`, and `ctx.extraColumns` returns
them after the columns of the option, marked `app`, so the block's functions
read and write them as `fields` and `addExtraColumns` leaves them to the app. A
table the app creates keeps the columns it has. The layout is part of the render
cache key.

The `extra-columns` codemod (`src/cli/codemod-extra-columns.ts`) moves the
option's columns into the app file that already alters the table, or into
`<table>.ext.sql` next to the app's schema files, and removes the option keys
from the config source. It finds each column's table in the files the blocks
render with the option, so it needs no table list. A column no block table adds
stays in the config and is listed. Doctor BS378 reports the options.

## Alternatives considered

Removing the option keys from the config schema and the 45 option specs in the
same change would leave every consumer with a config that fails validation
before the codemod can read it. The options stay accepted, and BS378 reports
them, until the codemod has run in both fixtures.

## Consequences

An app column and an option column give the same SQL, except that the block
adds only the option's column. Dropping the `*ExtraColumns` option specs, the
Create design's `extraColumns` and the `extra-columns` docs is still open.
