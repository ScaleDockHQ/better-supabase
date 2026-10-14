# 0023: The bookings block requires the btree_gist extension

- Status: accepted
- Date: 2026-10-13

## Context

A booking system must never let two customers book the same seat at the
same time. Checking for an overlap in a function and then inserting leaves a
race: two transactions can both see a free slot and both insert. Locking the
resource row serializes every booking on it and still trusts each write path
to take the lock, including direct writes by the service role.

Postgres solves this with an exclusion constraint: `exclude using gist
(resource_id with =, seat with =, blocked with &&)`. A GiST index supports
`&&` on ranges, but not `=` on `uuid` or `integer`. The `btree_gist`
extension adds those operator classes. It ships with Postgres (contrib), is
available on every Supabase project, and is on Supabase's list of trusted
extensions.

No other module installs an extension. The library's SQL so far runs on a
bare Supabase database.

## Decision

The `bookings` module runs `create extension if not exists btree_gist with
schema extensions` before its tables, and `bookings` carries the constraint
`bookings_no_overlap` on `(resource_id, seat, blocked)` where the status is
not `cancelled`. `blocked` is the booked range widened by the service's
buffers, kept in a check (`blocked @> during`). Capacity becomes seats: a
resource with capacity 3 has seats 1 to 3, and the booking function tries
each free seat, catching `exclusion_violation` for the next one.

The functions still check the slot first, so a caller gets
`BOOKING_SLOT_UNAVAILABLE` for a slot outside the hours, and the constraint
is the last word on a race. The error mapper reports `23P01` as the
`exclusion` kind.

## Alternatives considered

- **An advisory or row lock per resource.** It serializes bookings and only
  protects the paths that take it; a direct insert skips it.
- **A trigger that checks for overlaps.** Two concurrent transactions do not
  see each other's rows, so it has the same race unless it locks.
- **An exclusion constraint on `tstzrange` alone, keyed by a text column.**
  It still needs `=` on the key in a GiST index, so it still needs
  `btree_gist`.
- **One row per time slot.** It fixes the slot grid in the table, makes
  buffers and variable durations awkward, and multiplies rows.

## Consequences

Installing `bookings` creates `btree_gist` in the `extensions` schema when
it is missing; the role that applies the migration needs the right to create
it, which `postgres` has on Supabase. Uninstalling the module leaves the
extension, since other schemas may use it. Self-hosted Postgres without the
contrib extensions cannot install the module. Revisit if Postgres adds
equality to GiST for these types without the extension.
