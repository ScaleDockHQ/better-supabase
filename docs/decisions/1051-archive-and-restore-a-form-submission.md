# 1051: Archive and restore a form submission (lane Y2, slice 5)

- Status: accepted
- Date: 2026-11-15
- Amends: 1050

## Context

ADR 1050 found one entity in the second group whose status does not hide the
row: a form submission. `accepted` and `rejected` stay in `list_form_submissions`
and `form_nps`, and a reviewer who removes a submission deletes its answers,
score and review for good.

## Decision

`archive_form_submission` and `restore_form_submission` need the review
permission and record `form_submission.archived` and `form_submission.restored`
once. Archiving a row that is archived, or restoring one that is not, returns it
unchanged.

- The submissions table gains an optional `archived_at` column, and the
  submission JSON carries `archivedAt`.
- `list_form_submissions` hides archived rows by default and takes
  `include_archived` as a fifth argument, so the migration drops the four
  argument form. `form_nps` leaves archived answers out. `get_form_submission`
  still reads one by id, and a review of an archived row stays allowed.
- A draft is refused with `FORM_SUBMISSION_DRAFT`: it is the respondent's work
  in progress, not a record, and they purge it.
- `delete_form_submission` becomes `purge_form_submission` and
  `form_submission.deleted` becomes `form_submission.purged`. The purge
  permission is `permissions.purge`, falling back to `review`, so no role
  migration is needed (ADR 0851).

## Consequences

Breaking for callers of `deleteSubmission`, for sinks that match
`form_submission.deleted` and for `hooks.deleteSubmission`; the changeset and the
0.66 to 0.67 guide have the old-to-new table. A custom submissions table
without `archivedAt` gets neither function and keeps the four-argument list.
