---
"better-supabase": minor
---

The `projects` composite now installs comments, files, tags, the timeline, relations, saved views and record teams, and it ships a glue module for project updates and initiatives. `overview` reads one project for a page, `cards` reads the counts on a task list, and `dependencies` flags a blocking project whose target date is after the dependent's start.

Tasks treats a project as a subject, with archive, restore and remove, milestones, a triage accept, decline, duplicate and snooze, and optional per-project identifiers (`WEB-130` when `identifiers` is `"project"`). Iterations gain a cadence, a daily snapshot and a burnup. A notification can be snoozed, and a favorite can sit in a folder.

An existing `projects` install gains the new parts and the glue module on `upgrade`. Run `better-supabase upgrade` and generate a migration. The tasks module moves from version 9 to 10, notifications from 11 to 12, and collections from 2 to 3.
