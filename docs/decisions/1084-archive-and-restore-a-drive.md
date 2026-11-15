# 1084: Archive and restore a drive (lane Y2, slice 11)

- Status: accepted
- Date: 2026-11-15
- Amends: 1052

## Context

ADR 1052 gives the drive an archive. `drive_delete_drive` removes the drive
row, and the foreign keys remove every folder, file, grant and share under it.
Retiring a drive that nobody uses any more therefore costs its content.

## Decision

`archive_drive` and `restore_drive` need the share role on the drive, record
`drive.archived` and `drive.restored` once, and return the drive unchanged when
it already is in the target state.

- The drives table gains an optional `archived_at` column, and a drive reports
  it as `archivedAt`.
- `drive_list_drives` hides archived drives by default and takes
  `include_archived` as a fourth argument, so the migration drops the three
  argument form. `drive_get_drive` and every read of the nodes keep working.
- An archived drive refuses a new item (`drive_check_parent`), a rename and a
  share with `DRIVE_ARCHIVED` (SQLSTATE 55000).
- `drive_delete_drive` becomes `drive_purge_drive` and `drive.deleted` becomes
  `drive.purged`. Purging needs the share role, `permissions.purge` (falling
  back to the manage key) and an archived drive (`DRIVE_NOT_ARCHIVED`). A legal
  hold on any item still blocks it with `DRIVE_HELD`.

## Consequences

Breaking for callers of `deleteDrive` and for sinks that match `drive.deleted`;
the changeset and the 0.66 to 0.67 guide have the old-to-new table. A custom
drives table that lacks the column must map `archivedAt` to `null`; it then gets
neither function and keeps the three argument list.

Edits to files and folders that already exist stay governed by their own
roles. Archiving hides the drive and stops new content; it is not a lock.
