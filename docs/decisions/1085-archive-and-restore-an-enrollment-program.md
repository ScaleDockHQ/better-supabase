# 1085: Archive and restore an enrollment program (lane Y2, slice 12)

- Status: accepted
- Date: 2026-11-15
- Amends: 1052

## Context

ADR 1052 gives the enrollment program an archive. `delete_enrollment_program`
removes the program and every enrollment under it, with the steps each person
completed. A program that is retired but whose history still matters has only
`enabled: false`, which hides nothing.

## Decision

`archive_enrollment_program` and `restore_enrollment_program` need the manage
key, record `enrollment_program.archived` and `enrollment_program.restored`
once, and return the program unchanged when it already is in the target state.

- The programs table gains an optional `archived_at` column, and a program
  reports it as `archivedAt`.
- `enrollment_programs` hides archived programs by default and takes
  `include_archived` as a second argument, so the migration drops the one
  argument form.
- `enroll` and `save_enrollment_program` refuse an archived program with
  `ENROLLMENTS_PROGRAM_ARCHIVED` (SQLSTATE 55000). Existing enrollments stay and
  keep their progress.
- `delete_enrollment_program` becomes `purge_enrollment_program` and
  `enrollment_program.deleted` becomes `enrollment_program.purged`. Purging
  needs `permissions.purge`, falling back to the manage key, and an archived
  program (`ENROLLMENTS_PROGRAM_NOT_ARCHIVED`), because it removes the
  enrollments.

## Consequences

Breaking for callers of `deleteProgram` and for sinks that match
`enrollment_program.deleted`; the changeset and the 0.66 to 0.67 guide have the
old-to-new table. A custom programs table that lacks the column must map
`archivedAt` to `null`; it then gets neither function and keeps the one argument
list.
