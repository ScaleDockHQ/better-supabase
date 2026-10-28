# 0128: Brand starters, template schedules on reminders' rules, machines read from a workflow version

- Status: accepted
- Date: 2026-10-28

## Context

Three gaps showed up in white-label and operations apps built on templates,
state-machine and timeline.

A product that serves several brands ships different starters per brand.
Templates knew two scopes, an organization's own and the system ones, so
apps forked every brand starter into every organization by hand. ADR 0035
keeps brands out of the library: there is no brands table, only a column
the app keeps.

Recurring records (the monthly invoice, the weekly checklist) needed a
scheduled workflow with the `templates.apply` step. Apps without the
workflow modules wrote their own cron and their own idempotency.

A state machine's edges lived in the config, so changing a process meant a
deploy, while the same team already drew the process in workflow-editor.
And a record's timeline left out its status changes and the messages about
it, which apps unioned in themselves.

## Decision

Templates gain a third scope, `brand`. With `options.brand: { table,
column, tenant? }`, a starter that `sync` saves with a `brand` has no
organization and a brand, and every organization whose column holds that
brand reads, forks and applies it. The key and default indexes count the
brand. The brand stays a column of the app's table, read by a security
definer function that returns it only to a caller who may read templates
in that organization.

Recurring records are `template_schedules` rows whose rule lives in the
reminders module's `recurrence_rules` (subject type `template_schedule`),
so the rule format, time zone handling and expansion are reminders' own.
The client expands the rules (`recurring.schedule()`, a manifest schedule
every five minutes) and enqueues one `templates.recur` job per occurrence,
deduplicated on the schedule and the occurrence. The job claims the
occurrence in `template_schedule_runs`, applies the template with the key
`template-schedule:<id>:<occurrence>` and records the application. The
tables render only with reminders' `rrule` column; there is no second
recurrence engine.

A machine with `workflow: "<slug>"` reads its statuses and edges from the
published version of that workflow-editor definition. The stages are the
nodes with a string `config.stage`, a path between two stages through nodes
without one is an edge, and `config.returnsTo` adds back edges. A new
record pins the version in `subject_lifecycles.workflow_version_id` and
keeps its edges after a new version is published. The trigger refuses an
insert while the definition has no published version (`55000`).

The timeline gains two sources read as the caller: `transition` from the
state-machine's `status_history`, and `message` from the sent messages of
the record's messaging conversation.

## Consequences

- `TemplateScope`, `ActivitySource` and `StatusState` gain members, which
  breaks exhaustive switches over them; there is no shim.
- Two workers that claim one occurrence before either records it both call
  the type's `apply` with the same key; the type uses the key to return the
  first record, as the `templates.apply` step already requires.
- When `activitySink` also records `status.changed` or `message.sent`, a
  status change or a comment reaches a timeline twice, as an `event` and as a
  `transition` or `message`; views filter with `sources`. Message entries
  have the type `message.sent`, as the outbox event does.
- A workflow machine names its definition by slug in the config. The
  lifecycle defaults of ADR 0126 (`resolve_workflow_definition`) pick a
  workflow to start per subject type and don't change which version a
  machine reads.
- A workflow machine can't set `initial`, `transitions`, `order` or
  `lifecycle: false`, and needs workflow-editor.
- Every new table is adoptable and tenant-scoped through `bsb_tenant_scope`.
