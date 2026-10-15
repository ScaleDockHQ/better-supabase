---
"better-supabase": minor
---

The `work-items` SQL module and `better-supabase/blocks/work-items` add issues and tasks on pipelines. Installing work-items binds the `work_item` type in the pipelines module with one pipeline per team, Linear's categories (triage, backlog, unstarted, started, completed, canceled) and the stage's category as the item's `state`. Items have an identifier, a parent the table keeps free of cycles, several assignees (capped by `maxAssignees`), a priority from 0 to 4, an estimate, progress, start, end and due dates, a lock that keeps the dates, and optional projects and iterations. `update(changes)` applies grid edits and Gantt drags one by one, closing stamps `closedAt` and a close reason, `assign` notifies new assignees and makes each watch the item, and `tree` rolls progress up for a Gantt group.
