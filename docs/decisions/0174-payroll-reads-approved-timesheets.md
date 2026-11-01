# 0174: Payroll runs read the entries of approved timesheets

- Status: accepted
- Date: 2026-11-01

## Context

ADR 0155 collected every finished time entry of a period and left timesheet
approval to the app, which had to lock weeks before it created a run. A run
created too early paid hours that a manager had not approved.

## Decision

`time-tracking` renders `time_week_approved(tenant, owner_id, at)`: true when
the week an instant falls in has an approved timesheet. It reads the same
columns as `time_week_locked` (the `approved_at` column, or the `status` column
in status mode and per-employee mode) and follows `options.userTimeZone`.

`create_payroll_run` and `refresh_payroll_run` count a time entry only when its
week is approved. A week that is open, submitted or rejected adds no line, and
approving it adds its hours at the next refresh. The leave and shifts sources
are unchanged. There is no option to turn the filter off: an app that wants
unapproved hours pays from its own source.

## Alternatives considered

- An option `approvedOnly`. A payroll file with unapproved hours is the failure
  this decision removes, so the default is the only behaviour.
- Count the approvals block directly. The timesheet row already holds the
  decision in every mode, so the function reads it and stays in one module.

## Consequences

- A draft run created before the last approval is incomplete until refresh.
- The change is in the rendered SQL, so adopters run `upgrade` and generate a
  migration (it replaces `collect_payroll_lines` and adds one function).
- Amends ADR 0155.
