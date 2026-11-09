# 0325: Declare block columns on owned tables in the app's files

## Status

Accepted. Step 2 landed in ADR 0580.

## Context

ADR 0258 left one change open: a block over a table the app creates adds its optional columns with `add column if not exists`, while the plan says a missing column turns its feature off. Turning the default around removes the feature for every app that relied on the added column, and removed 460 lines of module SQL from the CentraKit fixture when it was tried.

## Decision

Step 1, landed here: `codemod owned-columns` renders the blocks, finds each `add column if not exists` on a table the app's files create when those files lack the column, and writes the statements to `<table>.block-columns.sql`. Doctor BS622 reports the same columns as a warning. The statements are the blocks' own, so the codemod changes nothing in a database that already has the columns, and a second run finds nothing.

Step 2, not landed: `ctx.has` on an owned table consults the app's declared columns, a module leaves out an `add column` for a table the app owns, and a missing column turns its feature off. It ships in a later release with a migration note, after apps have run the codemod. The CentraKit fixture is the check: after the codemod its module SQL must keep the same features with no `add column` on its own tables.

## Consequences

An app can declare every column before the flip, and doctor lists the ones it hasn't. The flip stays a separate, reviewable change.
