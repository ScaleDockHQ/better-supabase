# 0138: Plan shifts in their own block, checked against leave, qualifications and rest

- Status: accepted
- Date: 2026-10-30

## Context

Teams that work in shifts (care, retail, hospitality, warehouses, field
service) plan who works when a week or a month ahead. The library has the
parts around a roster: `employees` keeps contracts with hours per week,
`leave` keeps approved absence, `qualifications` knows who may work a shift
that needs a licence, `time-tracking` keeps worked hours and timesheets, and
`bookings` places appointments on resources. None of them holds a planned
shift with several places that members fill, publish and swap.

`bookings` comes closest, but a booking reserves a resource for one customer
and a shift is the other way round: one slot filled by several members,
planned in draft and shown to the team only when it is published. Putting
shifts on bookings would bend its availability rules and its customer-facing
API around a planner's workflow.

## Decision

A `shifts` block owns five tables: `shift_templates`, `shifts`,
`shift_assignments`, `shift_swaps` and `shift_availability`. Templates
generate draft shifts on their ISO weekdays, at most 92 days at a time, in
the block's `timeZone` (UTC by default); an end at or before the start runs
into the next day. Planners publish the drafts per range and team, and
members see only published shifts.

Every assignment, whether a planner assigns, a planner approves an open shift
request or a manager approves a swap, runs one check in SQL
(`shift_assignment_check`): no overlapping assigned shift (also an exclusion
constraint on the block's own assignments table, which is why the block
installs `btree_gist`), no approved leave on the shift's day when `leave` is
installed, the shift's required qualifications on its day when
`qualifications` is installed, and at least `minRestHours` (11 by default)
since the member's previous shift. `qualificationCheck: "warn"` turns the
qualification refusal into a warning returned with the assignment.

Four permissions split the work: `shifts.read` (members), `shifts.request`
(members: open shift requests and their own availability), `shifts.write`
(planners: templates, drafts, assignments, anyone's availability) and
`shifts.manage` (publishing, canceling, deciding requests and swaps, and the
hours report). Swaps are decided under `shifts.manage`; with `approvals`
installed the decision can link the approval request it came from, but the
block doesn't start one.

`shift_hours` reports planned hours per member and week next to the
contract's hours from `employees`. With `time-tracking` installed,
`shifts_to_time_entries` (service role) writes one time entry per worked
assignment with the subject `shift_assignment`, skipping submitted weeks and
overlapping entries.

The client follows ADR 0130 and the data contract: `upsert` saves a shift,
not `save`, and every table is adoptable through `tables` and `columns`.

## Alternatives considered

Shifts as bookings resources with a host (as ADR 0068 did for appointment
schedules) lost because a shift has a headcount filled by several members,
a draft and published state, and swaps; bookings would need all three only
for this case.

Checking leave and qualifications in TypeScript before the insert lost
because a planner, an open shift approval and a swap all assign, and a check
outside the transaction races with a leave approval or a revoked
qualification. The SQL check runs in the same transaction as the insert.

Starting an approval request for every swap lost because most teams let a
manager approve swaps directly; teams that want a formal approval start one
with the `approvals` block and pass its id when they decide.

## Consequences

A roster, an open shift board and a swap flow need no app SQL, and the
example app shows the week as a `roster-board` recipe. The block adds one
`btree_gist` extension and five tenant tables. The overlap constraint lives
only on the block's own assignments table; an adopted table relies on the
check in the assignment functions. Open shift requests hold no place until a
planner decides them, so two members can ask for the last place; the second
approval is refused with `SHIFT_FULL`. Revisit the swap decision if teams
need a colleague's consent before a manager sees the swap.
