# 0074: Billable time prices entries from a rate card; billed entries lock

- Status: accepted
- Date: 2026-10-22

## Context

Time tracking records billable entries with an optional rate, and invoices
hold lines in bigint minor units, but nothing turned one into the other.
Agencies and consultancies bill time per customer or project, with rates that
differ per member and change over time. Billing the same hour twice, or
changing an hour after it was billed, makes the invoice wrong without anyone
noticing.

## Decision

The `billable-time` module adds a rate card (`time_rates`): an hourly rate in
minor units and a currency, optionally for a member, a record or both, from an
effective day. An entry's own rate wins; otherwise the most specific rate on
the card applies (member on the record, record, member, organization), picked
by the day the entry started in the time-tracking block's time zone.

`invoice_from_time` selects finished, billable, unbilled entries, groups them
by record, member or entry, and creates a draft through `create_invoice` with
one line per group: hours to four decimals as the quantity and the hourly rate
as the unit amount, rounded to a minor unit per line. It fails while an entry
has no rate or the entries mix currencies without one picked, so an invoice is
never partial. Each billed entry gets a `time_invoice_entries` row with the
invoice, rate and seconds, in the same transaction.

A trigger on the entries keeps a billed entry's time, billable flag and rate
fixed and refuses to delete it. Voiding the invoice releases the entries. The
record isn't locked, so merging records keeps working.

## Consequences

- An hour is billed at most once, and what an invoice billed can be listed per
  entry with the rate it used.
- Deleting a billed entry raises `restrict_violation` (23001), so an
  organization purge retries the table after the invoices are gone. Erasing a
  member doesn't remove billed entries: they are accounting records until the
  invoice is voided.
- Rounding happens per line, so the invoice total equals the sum of its lines.
- Expenses and fixed fees aren't covered; they are invoice lines the app adds
  itself.
