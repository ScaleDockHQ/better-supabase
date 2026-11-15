# 1041: Where delete stays and where archive comes first (lane Y2, slice 3)

- Status: accepted
- Date: 2026-11-15
- Amends: 0346, 1028

## Context

EX-1207 found 48 entities that only delete: their event catalog has `.deleted`
and no `.archived`. ADR 0346 makes `archived_at` the soft delete column and
keeps a hard delete only as a `purge` behind its own permission. Adding an
archive to every one of them is wrong, because a delete is the right verb when
the row is not a record anyone needs back, and each archive costs a column, two
functions, two events, a list filter, a migration and golden SQL.

## Decision

An entity gets an archive and a restore when it holds a record that a person
entered or an outside party relies on, and a user can delete it by mistake. It
keeps its delete, with no archive, when its row is one of these:

| Entity                       | Block              | Why delete is the verb                                                    |
| ---------------------------- | ------------------ | ------------------------------------------------------------------------- |
| `reaction`                   | `reactions`        | A toggle: undoing a reaction deletes it, and nothing refers to the row    |
| `saved_view`                 | `saved-views`      | A user's own filter and column state, which is recreated in seconds       |
| `acknowledgement_assignment` | `acknowledgements` | A rule that names who must acknowledge; removing it is unassigning        |
| `team_member`                | `teams`            | A join row between a team and a member; the team keeps its own archive    |
| `field_value`                | `custom-fields`    | The value of one custom field on one record; clearing a value is a delete |

These five are decided here and recorded in the EX-1207 row. The other 43 entities stay
open and follow the order below, in slices of at most 80 files, each with its
own ADR number, migration and pgTAP test:

1. Records a person enters (`employee`, `expense`, `time_entry`,
   `announcement`, `post`, `activity`, `course`, `product`, `product_variant`,
   `meeting`, `calendar_event`, `funding_claim`, `maintenance_plan`).
2. Records that a lifecycle state already ends (an offboarded employee, a
   cancelled meeting, a rejected review): the archive must hide the same
   rows that the state hides, so each needs its read paths checked first.
3. Configuration and credentials (`flag`, `automation`, `connector`,
   `credential`, `oauth_client`, `incoming_webhook`, `hostname` and the other
   settings rows), where the lifecycle verb is revoke or disable and a
   delete is a purge. These are decided one at a time.

## Consequences

EX-1207 stays deferred to lane Y2 until slice 1 of the order above is done, then
becomes `fixed` when every remaining entity has an archive or a recorded reason in a
later ADR. Slices that rename a delete method to `purge` list the old and new
names in a changeset table and in the migration guide.
