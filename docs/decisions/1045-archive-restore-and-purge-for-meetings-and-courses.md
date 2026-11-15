# 1045: Archive, restore and purge for meetings and courses (lane Y2)

- Status: accepted
- Date: 2026-11-15
- Amends: 1041

## Context

ADR 1041 puts meetings and courses in its first group and ADR 1050 leaves the
meeting's cancelled state and the course's `archived` status to this slice. A
meeting is deleted while planned or cancelled and a held one could never be
hidden. A course already has an `archived` status, set through `save_course`.

## Decision

`meetings` gets an `archived_at` column (optional) with `archive`, `restore`
and `purge`. The archive does not repeat `cancelled`: it applies to a held or
cancelled meeting, hides it from `list_meetings` unless the `archived` filter
is set (`true` lists only archived ones), and an archived meeting takes no
changes until it is restored. `get_meeting` still returns it, so a link or an
action item keeps working. `purge` replaces `delete` for a planned or
cancelled meeting and needs `permissions.purge`, falling back to the creator,
chair, secretary or `meetings.manage`.

`courses` adds no column. `archive_course` sets the existing `archived`
status, which already hides the course from learners, and `restore_course`
brings it back as a draft so it is published again on purpose. Both record
`course.archived` and `course.restored` once, and do nothing when the course
is already in that state. `purge_course` replaces `delete_course` with the
same cascade and needs `permissions.purge`, falling back to `courses.manage`.

## Consequences

Breaking: `meetings.delete`, `delete_meeting`, `meeting.deleted`,
`courses.delete`, `delete_course` and `course.deleted`. The 0.66 to 0.67 guide
has the old-to-new table. `list_meetings` documents the `archived` filter.
