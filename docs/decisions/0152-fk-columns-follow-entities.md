# 0152: Foreign key columns follow the entity

- Status: accepted
- Date: 2026-10-31
- Supersedes: the foreign key line of 0147

## Context

0.47 renamed the task and activity entities and their tables, but left the
columns that point at them (`work_item_id`, `engagement_id`) with the old noun.
0147 kept those for 0.48. The table moves already run as upgrade steps, and
`NAMES.migrations` takes column moves, so the columns can move in the same
release.

## Decision

- `task_checklist_items.work_item_id` and `task_assignees.work_item_id` become
  `task_id`. `engagement_subjects`, `engagement_recordings` and `engagement_notes`
  take `activity_id` for `engagement_id`, and so does `mail_threads`.
- Each move is a `NAMES.migrations` entry with `columns`. `tasks`, `activities`
  and `mail-sync` go to SQL versions 4, 3 and 2.
- A column of a renamed entity starts from the old noun, as its table does
  (`columnBase`), so an install that names the entity keeps its columns.
- `codemod 0.47` lists lines that use `work_item_id` or `engagement_id`; it
  doesn't rewrite them, because an app's own tables use the same names.
- Logical column keys and the `engagementId` field of a mail thread don't change.

## Alternatives considered

- **Keep the old columns until 0.48.** Ships a release whose tables and columns
  disagree about the noun.
- **Rewrite the names in app SQL.** Would also rewrite the app's own columns.

## Consequences

- Adopted tables and mapped columns keep their names; a custom install that
  reads `engagement_id` from a thread row still works.
