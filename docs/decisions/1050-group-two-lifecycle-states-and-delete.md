# 1050: Group two, where a lifecycle state already ends the record (lane Y2, slice 4)

- Status: accepted
- Date: 2026-11-15
- Amends: 1041

## Context

ADR 1041 puts the entities whose lifecycle already has an end state in its
second group and says each needs its read paths checked before it gets an
archive: the archive must hide exactly the rows the state hides. Employees
(offboarded) and meetings (cancelled) are also in the first group, a record a
person enters, so slice 1 decides them. This slice reads the rest.

## Decision

Six entities keep their delete and get no archive. Each reason comes from the
block's own read paths.

| Entity               | End state or guard                                 | Read paths checked                                                                                   |
| -------------------- | -------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `review`             | `rejected`, reversible with `publish`              | `list_reviews`, `review_summary` and the stats trigger already read only `published`                 |
| `inspection_finding` | the inspection's `closed` state locks its findings | `delete_inspection_finding` refuses a closed inspection and a finding with a case                    |
| `case_action`        | none; the row links a case to a task               | The task keeps its own state, so removing the link loses no record                                   |
| `message`            | `archived_at` tombstone with an emptied body       | `delete_message` already soft-deletes; the event is `message.deleted` and the thread keeps its place |
| `version`            | none; the row is an immutable snapshot             | `restore` copies a version forward, and a delete is the retention purge                              |
| `organization`       | `deleteMode` `soft` or `lifecycle`                 | the app picks the mode (default `hard`), and member suspension is a separate state                   |

One entity gets an archive: `form_submission`. A reviewer can delete a
submitted, accepted or rejected submission, and the status says nothing
about whether the row is gone, so no state hides the same rows an archive
would. It follows in the next slice with its own migration.

## Consequences

ADR 1041's table lists the six. EX-1207 counts them as decided, and
`form_submission` stays open until its slice merges.
