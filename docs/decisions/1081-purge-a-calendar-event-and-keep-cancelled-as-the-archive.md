# 1081: Purge a calendar event and keep cancelled as the archive (lane Y2)

- Status: accepted
- Date: 2026-11-15
- Amends: 1041

## Context

ADR 1041 puts calendar events in its first group. An event already has a
`status` that ends in `cancelled`. Availability and free-busy skip a cancelled
event, and the ICS export writes it as `STATUS:CANCELLED`, so attendees see the
cancellation. `delete_calendar_event` removes the row with its overrides, and
`cancelOccurrence` calls it for a single event that is not part of a series.

## Decision

Calendar events get no `archived_at` column, `archive` or `restore`. A hidden
event that still counts as busy time or drops out of exports would contradict
the cancelled status that every consumer already reads. `delete_calendar_event`
becomes `purge_calendar_event` and records `calendar_event.purged`. Its key is
`permissions.purge`, then the former `permissions.delete`. Removing one
occurrence of a series (`cancel_calendar_occurrence`) keeps its `delete` key
because it adds an `EXDATE` and removes no row.

## Consequences

Breaking: `calendar.delete`, `delete_calendar_event` and
`calendar_event.deleted`. The `delete` key is still read when `purge` is unset,
so existing configs keep working. The 0.66 to 0.67 guide has the old-to-new
table.
