# 0374: The naming engine separates the block key from the entity plural

- Status: accepted
- Date: 2026-11-08
- Amends: 0349, 0130, 0152

## Context

A renamed entity (`task` to `ticket`) must not rename the permission keys of
the block that holds it: `tasks.read` is the `tasks` block's key, not the
`tasks` table. ADR 0349 kept `TABLE_RENAMES`, `spec.formerly` and
`functionNouns` for this, because a renamed install started from an old noun
(`work_item`) whose plural never matched the block key. Every module kept two
nouns, and the default render of the tasks block still wrote `work_item`.

## Decision

- An entity spec says `keyed: true` when its plural is also the block's name
  (tasks, activities, incidents, custom-fields, contracts, automations, goals,
  compliance, timeline). The rename engine skips `<plural>.` followed by a dot
  for those entities, so `tasks.read`, `tasks.*` and `tasks.completed` stay,
  while `task.created`, `list_tasks`, the `tasks/` subject paths and the table
  names follow the entity.
- `TABLE_RENAMES`, `spec.formerly`, `functionNouns` and the legacy column
  renamer are removed. The default noun of an entity is the noun its module
  source writes. The tasks block is written with `task` (functions' `task`
  argument, `taskId` payload key, `tasks/` subject path, `bsb_task_guard`),
  and `work_item` is only a name an app can give it.
- The built-in goal metric is `tasks.completed`, after the permission key.
  `20261108032000_bsb_task_nouns.sql` updates stored rows.

## Consequences

An app that named the entity `work_item` in `blocks.tasks.names` keeps its
tables and functions, and its event types follow the entity (`work_item.created`).
An app on the default names gets `task.*` events and a `taskId` payload key.
