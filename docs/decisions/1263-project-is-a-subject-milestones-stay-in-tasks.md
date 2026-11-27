# 1263: A project is a subject and milestones stay in tasks

- Status: accepted
- Date: 2026-11-26

## Context

A project row had a key, a name, an owner, a status, two dates and a budget.
It was not a subject, so comments, files, tags, favorites and search could
not attach to it, and it emitted no events. A milestone belongs to a project
and a task points at a milestone.

## Decision

The tasks module registers `project` as a subject and records
`project.created`, `project.updated`, `project.archived`, `project.restored`
and `project.deleted`. New columns cover the description, team, priority,
icon, color, rank, health and the date resolution. Members reuse record
teams, with the roles `lead` and `member`. `owner_id` stays and is the lead.
`project_milestone` is an entity in the same module: a task's `milestone_id`
must belong to the task's project. The Next.js example renames the block
subject to `work_project`, next to its existing `task` rename, because the
app already has a subject named `project`.

## Alternatives considered

A members table on the project would have copied record teams. A milestone
module of its own would have split a row that only exists for a task.

## Consequences

Anything that attaches to a subject can attach to a project. Facilities that
turn the projects table off still render, because the project SQL stays
behind `hasTable`.
