# 00XX: Book series one occurrence at a time, and pay for classes from a credit ledger

- Status: accepted
- Date: 2026-10-22

## Context

Studios, clinics and fitness apps book standing appointments and weekly
classes, and sell packs of classes. The `bookings` block refuses double
bookings with one exclusion constraint on the buffered range of each seat
(ADR 0023), and the `passes` block counts uses on a pass (ADR 0073). A series
has to keep that guarantee for every occurrence, and moving an occurrence has
to be checked by the same constraint. The repo standard puts balances in a
ledger, never in a parallel balance table, and new options default to off.

## Decision

With `recurring: true`, `bookings` adds `booking_series` and a `series_id`
column on `bookings`. `book_series` expands the rule in SQL
(`booking_series_starts`: daily or weekly, an interval, ISO weekdays, a count
of at most 366 and an `until`, in the rule's time zone so local times survive
daylight saving), then places every occurrence through the same
`place_booking` as a single booking. A taken occurrence fails the series, or
is skipped and reported with `skip_conflicts`. There is no stored RRULE and no
lazy expansion: every occurrence is a row the constraint checks.
`parseRecurrence` and `formatRecurrence` in the client map the RRULE subset to
this rule.

`move_booking` moves a booking by setting it to `cancelled` with the reason
`bs:moving` for the length of the check, so its own seat is free, then
checks the slot, sets the new range and restores the status; the exclusion
constraint settles a race and an error rolls the whole move back.
`reschedule_booking` with `following` moves later occurrences by the same
shift, latest first for a later time so the series never collides with
itself.

With `credits: true` and `bookings` installed, `passes` adds
`pass_credit_entries`: `-1` per booking and `+1` per refund, unique per
booking and reason, with `passes.uses` as the running total.
`book_with_credit` locks the pass, books through `hold_booking` and writes the
entry in one transaction. A trigger on the booking's status refunds once when
it is cancelled at least `creditRefundBefore` before it starts, and ignores the
`bs:moving` step.

## Alternatives considered

- Store the rule and expand occurrences on read. The exclusion constraint
  could not see future occurrences, so two series could claim the same seat.
- Move a booking with delete and insert. It would lose the booking's id, its
  ticket, its credit entry and its calendar uid.
- Defer the constraint during a move. Exclusion constraints on a gist index
  can be deferred, but a deferred check fails at commit, after the calendar
  and reminder mirrors ran, and the error no longer names the move.
- Keep a credit balance column on `passes` only. A refund would have no record
  of which booking it was for, and a second refund could not be refused.

## Consequences

A series is at most 366 occurrences and two years ahead, which covers weekly
classes and daily treatment plans; monthly rules would need a new `freq`. The
`bs:moving` reason is reserved, and a trigger that reacts to cancellations has
to ignore it the way the credit refund does. A credit booking is admitted at
the door with a ticket for the booking, because scanning the pack counts a
use. Adopted tables and custom mode get neither option.
