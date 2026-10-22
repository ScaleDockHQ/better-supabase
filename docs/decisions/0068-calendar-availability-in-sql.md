# 0068: Compute calendar availability in SQL and build appointment schedules on bookings

- Status: accepted
- Date: 2026-10-22

## Context

Phase 7 of the SaaS parity track asks for working hours, out of office,
focus time, free/busy and appointment schedules. Free/busy has to cover
recurring series, overrides, invitations and approved leave, for many
members at once, and it is read by people who can't read every member's
events. The `calendar` block expands recurrence in TypeScript
(`expandRule`, shared with reminders), and the `bookings` block already
computes open slots in SQL, holds them and refuses double bookings with an
exclusion constraint.

## Decision

Free/busy runs in Postgres. `calendar_rule_starts` is a PL/pgSQL port of
`expandRule` (FREQ, INTERVAL, COUNT, UNTIL, WKST, BYDAY with ordinals,
BYMONTHDAY, BYMONTH, BYSETPOS, and Temporal's choice of instant around
daylight saving changes). `calendar_busy_blocks` is a security definer
function for the service role that turns events, invitations and approved
leave into busy blocks, and `calendar_free_busy` returns merged ranges per
member to anyone with `calendar.read`, never the events themselves.
Events gain `kind` (`event`, `out_of_office`, `focus_time`), `transparency`
and `auto_decline`; working hours live in `calendar_working_hours`. The SQL
is in `src/sql/modules/calendar-availability.ts`, rendered by the calendar
module. An integration test runs both expanders over the same rules.

Appointment schedules are bookings resources with a `host_user_id` and
`check_busy`: `booking_slots` subtracts the host's busy blocks, minus the
calendar copies of that resource's own bookings. Rooms are resources with
`kind: "room"`. No new block or table is added for either.

## Alternatives considered

- Free/busy in TypeScript over `events()`: the client would need read access
  to every member's events and would load whole series for a one-day
  question.
- Materialized occurrences in a table: fast reads, but every series edit and
  every new window needs a rewrite, and a horizon decides what "forever" means.
- A separate appointment schedules block: it would duplicate slots, holds,
  the exclusion constraint and public booking that bookings already has.

## Consequences

The recurrence rules exist twice, so a change to `expandRule` needs the same
change in `calendar_rule_starts`; the parity test fails until both agree.
Auto-decline skips recurring blocks and recurring invitations. ADR numbers
0066 and 0067 are left for branches in flight; renumber this one if they
collide when it merges.
