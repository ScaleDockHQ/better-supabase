# 0148: Cases ask for approval and keep versions; inspections reach the calendar and notifications

- Status: accepted
- Date: 2026-10-31

## Context

Cases closed on blockers alone, kept no history of the closed record, and the
example's Close button hid for the case owner. Inspections scheduled in the
database only, told nobody about an assignment or a missed end date, and the
docs did not say that attachments already work on them.

## Decision

- `cases` integrates `approvals` and `versions`. A tenant policy for subject
  `case` and action `close` adds the blocker `CASE_APPROVAL_REQUIRED` until a
  request to close is approved. The approval's `approve` hook runs the
  service-only `case_close_approved`, which closes the case if no other blocker
  remains. Closing writes a version named `Closed <number>`.
- `inspections` takes a `calendar` option. With it, planned and running
  inspections that have a planned start keep one all-day event (uid
  `inspection-<id>`) in the named calendar.
- With `notifications`, joining an inspection team sends `inspection.assigned`,
  and `notify_overdue_inspections()` (the daily `overdue` schedule) sends
  `inspection.overdue` once per planned end. Both use an idempotency key.
- The example's Close button also shows for the case owner.

## Alternatives considered

- **Ask for approval in the floor.** A floor with steps would block every
  tenant. The floor stays empty so tenants opt in.
- **A column for the last notification.** The key already dedupes assignments;
  only the overdue report needs `overdue_notified_for`.

## Consequences

- An approval stays valid for the case, so a reopened case does not ask again.
- The calendar block cannot be in custom mode when `calendar` is set.
