# 0018: Subject bindings carry their own adopted tables

- Status: accepted
- Date: 2026-10-13

## Context

Blocks such as attachments store one polymorphic table (`subject_type`,
`subject_id`) and learn the subject's table from `options.subjects`. Apps
that already shipped keep one link or history table per entity
(`task_tags`, `quote_status_history`). One `tables.<logical>` mapping cannot
name those tables, and adopt mode would otherwise require the app to move
its rows first.

## Decision

`options.subjects.<type>` may carry a module-specific table binding, parsed
by `subjectTableBinding` in `src/sql/subjects.ts`. The binding names the
adopted table and the physical columns. In managed mode the module still
writes one polymorphic table. In adopt mode, functions branch on
`subject_type` and write the binding's table. `adoptSubjectTables` on the
module reports those tables to `adoptedColumnProblems` and `adoptedTables`,
so a missing column is refused the same way a mapped module column is.

Tags, the state machine, custom fields, share links and reminders use it.

## Alternatives considered

- **One polymorphic table only.** Adopt mode would not fit the tables these
  apps already have.
- **A free-form SQL fragment per subject.** It cannot be checked against the
  declared columns, and each module would parse it differently.

## Consequences

A new subject-bound block declares the binding keys it reads and implements
`adoptSubjectTables`. Adding a column to a binding is a module change, with
the same adopt-mode null mapping as any other optional column.
