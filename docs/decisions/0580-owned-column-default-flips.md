# 0580: Turn a feature off when an owned table lacks its column

## Status

Accepted. Replaces the deferral in ADR 0373 and lands step 2 of ADR 0325.

## Context

ADR 0373 held the flip until the renames merged. They have, and `codemod owned-columns` and doctor BS622 have shipped for a release, so apps can declare the columns blocks add to their own tables.

## Decision

`ctx.has(table, column)` is false for a table the app owns when the layout knows the table's columns and the column is not among them. Modules guard their optional columns and SQL with `ctx.has`, so the `add column if not exists` statement and every use of the column disappear together, the same way a column mapped to `null` does. A table whose columns are unknown, and every table a block owns, behave as before.

`codemod owned-columns` and doctor BS622 render with `layout.keepUndeclaredColumns`, which restores the old behavior, so they still find the columns the flip would turn off. The migration note in the 0.57 to 0.58 guide says to run the codemod before `upgrade`.

## Consequences

An app that did not run the codemod loses the features whose columns its table lacks. The next `upgrade` output shows the missing statements, and doctor BS622 lists the columns. Declaring them restores the feature. The CentraKit and example fixtures declare theirs, and a unit test covers the flip and its opt-out.
