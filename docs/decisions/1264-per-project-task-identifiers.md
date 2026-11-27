# 1264: Per-project task identifiers are opt-in

- Status: accepted
- Date: 2026-11-26

## Context

Every task is numbered `TASK-12` for the tenant, and the unique key is
`(tenant, number)`. A project page wants `WEB-130` from that project's own
counter. The numbering helper's scope is a legal entity, not a project, so
it cannot do this on its own.

## Decision

`identifiers: "project"` on the tasks block numbers a task from its project's
key and a per-project counter. The unique key becomes `(tenant, identifier)`.
The default stays `identifiers: "tenant"` and `TASK-12`. A move between
projects assigns a new identifier. `task_identifiers` keeps the old one, and
`resolve_task_identifier` finds the task by either.

## Alternatives considered

Always using the project key would have changed every existing identifier.
Reusing the numbering scope would have filtered on the legal entity and
missed the project.

## Consequences

The option is off until an app sets it. Turning it on rewrites the unique
key in the upgrade from tasks version 9, so a database that already has two
tasks with the same identifier in different projects needs a check before
the upgrade.
