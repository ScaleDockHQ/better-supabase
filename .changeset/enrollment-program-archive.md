---
"better-supabase": minor
---

Breaking: `enrollments` gets `archiveProgram` and `restoreProgram`, and the hard
delete of a program is `purgeProgram`, behind its own `permissions.purge` key
(it falls back to `enrollments.manage`) and only for an archived program. An
archived program leaves `programs()`, and `enroll` and `saveProgram` refuse it
with `ENROLLMENTS_PROGRAM_ARCHIVED`; its enrollments stay. `programs()` takes
`{ includeArchived }`, and a program carries `archivedAt`.

| Before                                | After                                         |
| ------------------------------------- | --------------------------------------------- |
| `deleteProgram(id)`                   | `archiveProgram(id)`, then `purgeProgram(id)` |
| `delete_enrollment_program(id)`       | `purge_enrollment_program(id)`                |
| event `enrollment_program.deleted`    | event `enrollment_program.purged`             |
| `enrollment_programs` with 1 argument | a second argument, `include_archived`         |

New events are `enrollment_program.archived` and `enrollment_program.restored`.
Run `better-supabase upgrade` and apply the migration. See the 0.66 to 0.67
guide.
