# 1184: Optional columns follow the table the app declares

- Status: accepted
- Date: 2026-11-22

## Context

A block over a table the app owns used to learn which optional features to turn
on from the config. `blocks.leave.columns.requests.startPart` was a switch, not
a rename: mapping it to its own default name (`start_part`) turned the parts of
the day on. About 90 CentraKit entries are such identities, and every `null`
for a column the table lacks restated what the render already did. ADR 0580
made `ctx.has` consult the columns the app's files declare, but the leave
module and a dozen others still read `ctx.config.columns` directly.

## Decision

The table decides, and the config only renames.

- `ctx.declares(table, column)` is true for a table of the app's that declares
  the column, and false for a block's own table and for a table whose columns
  are unknown. The leave module asks it for the parts of the day
  (`startPart` and `endPart`, declared together or refused), for confidential
  types and for auto-approving types. No config entry switches them on.
- `ctx.has` keeps its answer: true on a block's own table, and on an app table
  true unless the layout lists the table's columns and lacks this one.
- A block adds no optional column to a table the app owns. BS622 now covers the
  required columns only, because the render without `keepUndeclaredColumns` is
  the one that runs; `codemod owned-columns` still declares an optional column
  on request.
- A `null` for an optional column that the app's table lacks, and an identity
  entry, are removed by `codemod config --prune`. Doctor lists the nulls it can
  see in a view; the codemod reads every table's columns from the schema files.
- Modules that still read `config.columns` to switch a feature on (catalog,
  invoices, profiles, webhooks and a few more) convert one by one, each with
  its own changeset.

## Alternatives considered

- Convert every module at once: each switch has its own default and tests, and
  the leave module covers the CentraKit entries that matter. The list keeps the
  rest visible.
- Refuse a column entry on a block's own table: the old leave errors did, but a
  harmless entry is better pruned than refused.
- Doctor error for an app table with unknown columns: the CLI layout always
  lists the columns of a table it owns, from the schema files or the snapshot,
  so the case cannot occur there.

## Consequences

A project that declared `start_part` and `end_part` and mapped them to their
own names keeps the feature and can delete the entries. A project that mapped
the columns but never declared them loses the feature until the table declares
them. A project that mapped `types.confidential` over the block's own table no
longer gets an error; the entry does nothing and is pruned. The 0.82 to 0.83
guide says so.
