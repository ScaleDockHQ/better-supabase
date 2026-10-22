# 0086: Log confirmed bookings as engagements with a trigger on the bookings table

- Status: accepted
- Date: 2026-10-22

## Context

A sales rep wants a booked demo on the contact's timeline next to calls and
emails. The bookings block knows the customer's name, email and user, and
the engagements block keeps the timeline, but nothing connects them. A
booking is confirmed from three places: `confirm`, `hold` with `confirm`,
and the public booking link, which runs as the guest. It can also be
written directly by the app or a sync.

## Decision

`blocks.engagements.options.bookings: true` renders a security definer
trigger, `bookings_engagement`, on the bookings table
(`src/sql/modules/engagements-bookings.ts`). When a booking becomes
confirmed, it upserts a `meeting` engagement with the external ref
`booking:<id>`, which is unique per organization. A reschedule of a
confirmed booking moves it, and a cancel after confirming completes it
with the outcome `cancelled: <reason>`. With `parties` installed, the
meeting links the person matched by user, then by email in any case, and
that person's first company. The events are the ordinary
`engagement.logged`, `engagement.updated` and `engagement.completed`.

The option is off by default. It fails at render time without the bookings
block or without `meeting` in `options.types`. Bookings stays unaware of
engagements: the integration lives in the engagements module, which
already depends on the registry that parties write into.

## Consequences

- Every confirmation path is covered, including direct writes and guests,
  because the trigger runs in the database, not in the TypeScript client.
- App code that logs the same booking with the ref `booking:<id>` updates
  the trigger's engagement instead of adding a second one.
- A booker with no contact gets a meeting on no record, which every reader
  of the organization sees. Linking it later is an `update` with
  `subjects`.
- The trigger function is not callable by `anon` or `authenticated`.

## Alternatives considered

- A TypeScript hook on `confirm`: misses the public link and direct writes.
- An outbox consumer: needs the outbox and a worker, and the meeting would
  lag the booking.
- Registering bookings as a subject and linking the meeting to it: the
  timeline a rep reads is the contact's, and a booking subject would need
  read policies for guests.
