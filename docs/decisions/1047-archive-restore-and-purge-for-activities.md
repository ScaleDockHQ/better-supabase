# 1047: Archive, restore and purge for activities (lane Y2)

- Status: accepted
- Date: 2026-11-15
- Amends: 1041

## Context

ADR 1041 puts `activity` in its first group. An activity feeds a record's
timeline, its next step, a member's open tasks, search, recordings and notes,
and a locked note must stay unchanged.

## Decision

`activities` gets an `archived_at` column (optional) with `archive_activity`,
`restore_activity` and `purge_activity`. An archived activity leaves
`activities_of` unless `archived` is set (`true` lists only archived ones),
`next_activity`, `open_activities`, search (the subject registry names
`archivedAt` as its `deletedAt`) and the pending recordings. It takes no
changes, including a note amendment, until it is restored. `get_activity` and
the row policies still read it, so a link, the archived list and `restore` keep
working. Export is unchanged.

A locked activity (`lockedAt` in the past) is not archived, so the lock keeps
its meaning. `purge` replaces `delete` and needs `permissions.purge`, falling
back to the owner, the creator and `activities.manage`.

## Consequences

Breaking: `activities.remove`, `delete_activity` and `activity.deleted`. The
0.66 to 0.67 guide has the old-to-new table.
