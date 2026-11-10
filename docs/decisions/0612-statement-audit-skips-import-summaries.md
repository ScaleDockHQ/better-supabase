# 0612: Statement audit skips import summaries

- Status: accepted
- Date: 2026-11-10
- Amends: 0435

## Context

`audit(statement => true)` writes the log and the restricted rows. The statement
triggers had no `when` clause, so a summary-mode import still built the
transition tables and entered the function. The row trigger already skips that
mode in `when`.

## Decision

The three statement triggers carry the same `when` clause as the row trigger:
`better_supabase.import_run()` is null, or the import is not in summary mode.
A statement `when` clause may call a function, and it does not read the
transition tables.

## Alternatives considered

- Leave the check inside the function. The transition tables are built first,
  which is the cost a bulk import pays before the function returns.

## Consequences

A summary-mode import does not run the statement audit function. The row
trigger stays the default.
