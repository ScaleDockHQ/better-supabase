# 0177: Maintenance plans take calendar rules and required qualifications

- Status: accepted
- Date: 2026-11-01

## Context

ADR 0160 gave maintenance plans two triggers, a number of days and a meter
advance. Real schedules are calendar shaped ("first Monday of the month"), and
ADR 0160 left out any link to `qualifications` (ADR 0132), so nothing stopped an
unqualified person from taking a weld inspection or signing a calibration.

## Decision

- A plan kind `rrule` carries an RFC 5545 `rrule`, a `dtstart` and a `tz` (an
  IANA zone, `UTC` by default). The rule must name a `FREQ` of `DAILY`, `WEEKLY`,
  `MONTHLY` or `YEARLY`. The occurrences are expanded in SQL by the same
  `ruleStarts` expander the calendar block uses, instantiated as
  `maintenance_rule_starts`, and `maintenance_next_occurrence` returns the first
  one after a date within ten years.
- `next_due_at` of an `rrule` plan is the next occurrence after the later of the
  last completion and the old due date, so late work never leaves a backlog of
  missed occurrences. Updating the rule, `dtstart` or `tz` recomputes it.
- Plans gain `required_qualifications text[]` and calibrations gain
  `qualifications text[]`, both qualification type keys, default empty. With
  `qualifications` installed (`integrates`), a key that is not a type is refused
  on save, a trigger on the work order's technician column refuses a technician
  who does not hold every required qualification today (`MAINTENANCE_UNQUALIFIED`),
  and `record_calibration` applies the same check to the person performing it.
  Without `qualifications` the lists are stored and not checked.

## Consequences

The four new plan columns and the calibration column are `not null` with defaults.
Apps that adopted the maintenance tables (ADR 0098) add them before upgrading. The
trigger runs `security definer`, so the check cannot be skipped by a role that
cannot read the qualification tables.

## Alternatives considered

- A separate `maintenance_schedules` table: one more table for something a plan
  already is.
- Checking qualifications in dispatch: dispatch would need to know about plans and
  qualifications, which the integration direction forbids (ADR 0010).
