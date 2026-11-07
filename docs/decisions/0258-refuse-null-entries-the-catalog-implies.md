# 0258: Refuse null entries the catalog already implies

- Status: accepted
- Date: 2026-11-07
- Amends: 0098

## Context

A block over a view the app owns already treats each optional column the view
lacks as mapped to `null` (`viewColumns`), yet configs and `add --adopt` still
wrote `columns.<table>.<column>: null` for it, and a tenant entry that repeats
`sql.tenantColumn` restated what the setting does.

## Decision

`viewColumns` (`src/sql/view-columns.ts`) refuses a `null` entry for an optional
column the view lacks anyway, with a message that names the entry. A `null`
entry for a column the view has stays valid: it turns the feature off on
purpose. `proposeAdoption` no longer writes the null entries for a view. A
`columns.<table>.tenant` entry equal to `sql.tenantColumn` is an error in
`ctx.col`.

A table the app owns keeps its `null` entries. There the block adds a missing
optional column with `add column if not exists`, so the entry says "do not add
it" and the catalog does not imply it. Turning that default around (the block
never adds a column to the app's table) is a separate change: it would remove
`install_field_pack` and most of the notifications module from CentraKit until
its files add the columns, so it needs its own migration path.

A config the view context can't validate alone (a provider option) leaves its
block to the full render.

## Alternatives considered

Inferring the feature off for every table the app owns follows the plan's
"a missing column turns its feature off", and it was tried: the CentraKit
fixture lost 460 lines of module SQL for columns the block used to add. That
change waits for the codemod that writes those columns into app files.

## Consequences

The null entries a view needs go away, and a stale one fails the render with
the entry to remove. Numbering already takes its tenant column from the subject
registry, and `sameTenant: { auto: true }` already reads foreign keys; making
both the default is not part of this change.
