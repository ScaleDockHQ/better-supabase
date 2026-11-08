# 0373: Keep the owned-column default flip deferred

## Status

Superseded by 0580

## Context

ADR 0325 step 2 makes `ctx.has` on an owned table read the app's declared columns, drops `add column if not exists` from modules for tables the app owns, and turns a feature off when its column is missing. The CentraKit fixture is its check. It holds 88 such statements across 24 module files, and `ctx.has` is read by most block modules, so the flip touches nearly every module's SQL. The block and table renames in progress on the main branch edit the same files.

## Decision

Step 2 does not land in this change. The codemod, doctor BS622 and the fixture check from ADR 0325 stay as they are. Before the flip, run `codemod owned-columns` on the CentraKit fixture and on the examples, commit the `*.block-columns.sql` files, then change `ctx.has` for owned tables in one commit that starts after the rename work merges, so the module diff is the only change. The flip needs a migration note and a major-version changeset.

## Consequences

No output changes. The flip stays a separate, reviewable change with a measured size of 88 statements in the fixture.
