# 0166: Purchase lines and expense lines carry dimensions for project costs

- Status: accepted
- Date: 2026-10-31

## Context

`projectCosts` sums accounting lines by `dimensions->>'project'`. A purchase
bill had one `dimensions` object on its header and an expense report had none,
so a bill or report that served two projects could only be booked to one, or
to none.

## Decision

`invoice_lines` and `expense_lines` get a `dimensions jsonb not null default '{}'`
column (an object, checked). Over a table of yours the column is added with
`add column if not exists` and the functions render it only when it exists.

- A purchase bill line's dimensions are merged over the bill's by key, line
  winning. Lines are grouped by tax rate, code, clearing account and dimension
  set, so equal sets still share one expense line.
- An approved expense report books one expense line per distinct dimension
  set, with a single total line when no line has dimensions.
- Sales lines ignore the column.
- `add_expense_line` and `update_expense_line` take `dimensions` as an eighth
  argument. A lines table without the column refuses a value with
  `EXPENSE_DIMENSIONS_UNSUPPORTED`.
- Accounting still validates the keys (`ACCOUNTING_DIMENSION_INVALID`).

## Alternatives considered

- A project column on lines: rejected, since dimensions already carry cost
  centres and the ledger validates them.
- Splitting a bill into several bills: rejected, since the supplier sends one
  document and the three-way match runs against it.

## Consequences

Project costs come out right for shared bills and reports. The column is part of
the migration for every adopter, and callers of the two expense functions by
position need the new argument or a named call.
