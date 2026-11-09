# 0436: Import targets may write a batch in set-based statements

- Status: accepted
- Date: 2026-11-09
- Amends: 0141

## Context

`import_apply_batch` called the target's `write` once per item inside its own
subtransaction. The scale report asked for set-based batch targets for a speed-up
of about five times, with a parity test.

## Decision

A target may name `batch`, `(run uuid, items jsonb) returns jsonb`. The loop still
classifies every item one by one (unchanged, conflicted, alias reuse), but the
items that need a write are collected and handed to `batch` once. The answer has
one entry per item, in order, either what `write` returns or `{ "error": ... }`.
Each answer goes through the same record-map code as before, so counts, record map
rows, warnings and errors are the same. When `batch` raises or answers the wrong
length, each collected item is written by `write` in its own subtransaction, so a
bad row costs only its own error. A key that repeats in a batch flushes the
collected items first, so the later item sees the earlier one as it did before.
Entities without `batch` run the old inline path, and the generated SQL for an app
with no batch target does not change.

Collected items live in `jsonb[]` variables: a first version built a `jsonb` array
by concatenation and was six times slower because every append copied the array.

## Measured

`supabase/tests/scale/scale_import_batch_targets.test.sql`, 3,000 new customers on
the local fixture: 356 and 366 ms through `public.import_customer_batch`, 365 ms
(and one cold run of 2,464 ms) through the one-row `public.import_customer`. There
is no speed-up here: the time is in the triggers on `customers` (search, audit
guards, defaults), which a set-based target cannot skip. A target whose per-row cost
is in its own function body gains; the fixture does not show it, and the five times
of the scale report is not reproduced. The reason to keep the option is that apps
whose write function does several lookups per item can move them into one statement,
and the parity test makes that safe.

Parity: `import_batch_target_parity` runs both paths on the same 200 items, a rerun
with 50 changes, a repeated key and a refused row, and compares counts, errors,
customer rows and record map shape.

## Consequences

`better-supabase upgrade` rewrites the `imports` module and the next schema
migration replaces `import_apply_batch`. No data migration. `batch` is optional, so
no app changes unless it adopts it.
