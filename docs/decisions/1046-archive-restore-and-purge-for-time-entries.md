# 1046: Archive, restore and purge for time entries (lane Y2)

- Status: accepted
- Date: 2026-11-15
- Amends: 1041

## Context

ADR 1041 puts `time_entry` in its first group. An entry could only be deleted,
and a read path review shows that it feeds more than the list: timesheet totals,
the overlap constraint, the approval lock, billable and unbilled selection,
project costing, funding deliveries, payroll export and the metrics.

## Decision

`time_entries` gets an `archived_at` column (optional) with `archive_time_entry`,
`restore_time_entry` and `purge_time_entry`. An archived entry leaves
`list_time_entries` unless `archived` is set (`true` lists only archived ones),
the timesheet and status totals, the billable, unbilled and costing selections,
funding deliveries, payroll export and the metrics, and `resume_timer` refuses
it. The overlap exclusion constraint becomes partial (`where archived_at is
null`), so an archived entry never blocks a new one, and `restore` checks the
overlap again (`TIME_ENTRY_OVERLAP`).

The week lock covers the archive. `archived_at` joins the default
`lockedColumns`, so the guard trigger refuses an archive or a restore in a
submitted or approved week with `TIME_PERIOD_LOCKED`, and purge hits the same
guard through its delete. An archived entry can therefore never be restored
into a locked period: the timesheet is reopened first. A running timer and an
invoiced entry are not archived. Billing columns include `archived_at`, so an
archived entry is never invoiced. `purge` replaces `delete` and needs
`permissions.purge`, falling back to the entry's member (with track) and
`time_entries.manage`. Shift reports read shifts, not entries, and are
unchanged.

## Consequences

Breaking: `timeEntries.remove`, `delete_time_entry` and `time_entry.deleted`.
The 0.66 to 0.67 guide has the old-to-new table. The module is version 4 with
an upgrade step that adds the column and rebuilds the constraint.
