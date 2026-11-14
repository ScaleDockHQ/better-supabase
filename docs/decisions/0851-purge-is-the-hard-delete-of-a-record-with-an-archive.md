# 0851: Purge is the hard delete of a record with an archive

- Status: accepted
- Date: 2026-11-14

## Context

EX-1207: 58 blocks delete, and most have no archive, so a "delete" is the only
way to remove a record and the name tells the caller nothing. Where a record
already archives (ADR 0839 pairs every archive with a restore), a method
called `delete` next to `archive` reads as the normal way to remove it, and a
mistyped call destroys the row and its members.

## Decision

Where a record entity has `archive`, its hard delete is named `purge`. It sits
behind its own permission key, `permissions.purge`, which falls back to the
block's `manage` key so an app that never named a key keeps working, and it
records `<entity>.purged`. `delete` stays the name for records that have no
archive (drafts, join rows).

This slice renames the one block where the same record has both: `teams`
(`delete` to `purge`, `delete_team` to `purge_team`, `team.deleted` to
`team.purged`, `permissions.delete` to `permissions.purge`). The other 57
`delete` methods name drafts, join rows or records without an archive, and
get an archive first in later slices before they can rename.

## Alternatives considered

A flag on `archive` (`archive(id, { hard: true })`) hides the destructive path
inside the safe verb. A new default key such as `teams.purge` would need a
role migration for every app, so the fallback to `manage` stays until a
permission set asks for the split.

## Consequences

Breaking for `teams` callers, sinks that match `team.deleted` and configs with
`permissions.delete` on the teams block; the 0.66 to 0.67 guide has the
old-to-new table. The `purge` name is now reserved in `EntityMethod` for the
manifest `emits` map.
