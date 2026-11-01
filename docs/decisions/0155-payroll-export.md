# 0155: Payroll runs collect in SQL and render through a versioned port

- Status: accepted
- Date: 2026-10-31

## Context

Payroll providers want one file per period: the hours each person worked and the
leave they took. The repo holds those facts in `time-tracking`, `leave` and
`shifts`, but nothing adds them up for a period, and nothing stops the same days
from going to payroll twice. Every provider has its own file layout, and an
organization may pay from tracked hours or from the roster.

## Decision

`payroll-export` is a block (`better-supabase/blocks/payroll-export`) with two
tables, `payroll_runs` and `payroll_lines`. Every table is adoptable (ADR 0098).

- Collection runs in SQL. `create_payroll_run` and `refresh_payroll_run` rebuild
  the lines of a draft run from the sources in `options.sources`, over the
  tables of `time-tracking`, `leave` and `shifts` through `ctx.of`. The default is
  the installed ones of `time-tracking` and `leave`. Shifts are opt-in because
  scheduled hours overlap tracked hours; naming a source that is not installed
  fails the render.
- Rendering runs in TypeScript behind `PayrollExportFormat`, a versioned port
  (`apiVersion: 1`) typed structurally, with a reference `csvPayrollFormat`. A
  provider's layout is a package that implements the port.
- `exportRun` renders the file, hashes it with Web Crypto and calls
  `mark_payroll_run_exported`, which keeps the format name and checksum, locks the
  run and emits `payroll_run.exported`. The same file exports again without a
  change; a different file is refused (`PAYROLL_RUN_EXPORTED`).
- A run for a period that overlaps an exported one is refused
  (`PAYROLL_PERIOD_EXPORTED`), so nobody is paid twice for the same days.
- Permissions are `payroll_export.read` and `payroll_export.export` (ADR 0130).
  Admins hold both; members hold neither.

## Alternatives considered

- Render in SQL. Provider layouts change often and carry provider logic, which
  belongs in a package, not in a migration.
- Collect in TypeScript. It would read every time entry through the API and
  could not lock a period in the same transaction.
- Require approved timesheets. `time-tracking` has no single approval shape that
  every owner mode shares, so the docs tell the app to lock weeks first.
  (ADR 0174 reverses this: `time_week_approved` reads the shape in every mode.)

## Consequences

- A format package implements one function and gets locking, checksums and the
  overlap guard for free.
- Time entries are filtered by timesheet approval since ADR 0174.
- The format port is a public extension interface; a breaking change needs
  `apiVersion: 2`.
