---
"better-supabase": minor
---

Breaking: `drive` gets `archiveDrive` and `restoreDrive`, and the hard delete of
a drive is `purgeDrive`, behind its own `permissions.purge` key (it falls back
to `drive.manage`) and only for an archived drive. An archived drive leaves
`drives()`, and it refuses new items, a rename and a share with `DRIVE_ARCHIVED`;
its content stays and stays readable. `drives()` takes `includeArchived`, and a
drive carries `archivedAt`. A legal hold still blocks the purge.

| Before                          | After                                     |
| ------------------------------- | ----------------------------------------- |
| `deleteDrive(id)`               | `archiveDrive(id)`, then `purgeDrive(id)` |
| `drive_delete_drive(id)`        | `drive_purge_drive(id)`                   |
| event `drive.deleted`           | event `drive.purged`                      |
| `drive_list_drives` with 3 args | a fourth argument, `include_archived`     |

New events are `drive.archived` and `drive.restored`. Run `better-supabase
upgrade` and apply the migration. See the 0.66 to 0.67 guide.
