# 1042: Archive, restore and purge for announcements (lane Y2, slice 5)

- Status: accepted
- Date: 2026-11-15
- Amends: 1041

## Context

ADR 1041 gives a record that a person enters an archive and a restore, and
ADR 0851 names the hard delete of a record with an archive `purge`. An
announcement is written by staff and shown to many people, and `remove` deleted
it and its dismissals with no way back.

## Decision

`announcements` gets `archive(id)`, `restore(id)` and `purge(id)`.

- An `archived_at` column (optional, so an adopted table may omit it, in which
  case the archive functions do not exist) marks an archived announcement.
- `archive` and `restore` need `announcements.manage`, return the announcement and
  record `announcement.archived` and `announcement.restored` once, doing nothing
  when it is already in that state.
- `purge` replaces `remove` and `delete_announcement`. It needs
  `permissions.purge`, which falls back to `announcements.manage`, and records
  `announcement.purged`. `announcement.deleted` is gone.
- Read paths: `active_announcements` never returns an archived row (an archived
  announcement stops showing at once), `list_announcements(include_archived)` hides
  it unless asked, and the dismissals, the Realtime broadcast and the data
  export keep working because the row stays.

## Consequences

Breaking: `announcements.remove`, `delete_announcement`, the
`announcement.deleted` event and sinks that match it. The 0.66 to 0.67 guide
has the old-to-new table. `list_announcements` takes an argument, so the
migration drops and recreates it.
