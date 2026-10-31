# 0150: Decide the remaining block overlaps and file each block under one docs group

- Status: accepted
- Date: 2026-10-31

## Context

The naming audit behind ADR 0130 left six overlaps open (ADR 0131 settled
the four it could do in one minor), and it found seven blocks whose manifest
category puts them in a docs group that does not match what they do. Each
overlap needs a decision, so that later plans and presets don't pick a side
by accident.

## Decision

Each pair is decided on what the two blocks store and who calls them.

| Overlap                                                                                  | Decision                                                                                                          |
| ---------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `collections` and `saved-views`                                                          | Stay separate. A view stores a filter and a list stores records. No merge.                                        |
| `pipelines` and `state-machine`                                                          | Stay separate and layer: pipelines own the editable stage tables, the state machine owns the allowed transitions. |
| `reminders`, `calendar`, `ai-schedules`, queue and workflow schedules                    | Stay separate by job. The three cron-driven ones share one SQL helper; recurrence stays in `reminders`.           |
| `workflows`, `workflow-editor`, `workflow-sdk`, `automations`, `sequences`               | Stay separate as layers of one stack. `automations` gains a way to start a published workflow.                    |
| `api-keys`, `service-accounts`, `oauth-server`, `signing-keys`, `credentials`, `ai-keys` | Stay separate: they secure different directions. A docs table compares them.                                      |
| `sso` domains and `domains` hostnames                                                    | Stay separate. One maps an email domain to a membership, the other maps a hostname to an organization.            |

### Collections and saved views

A saved view stores a filter tree, so its rows change with the data. A list
in `collections` stores the records. Both share the same three owners (user,
team, organization), which is a likeness of the UI, not of the data. Merging
them would make one table hold either a query or a set of keys. The pages
already link to each other, and that stays the answer.

### Pipelines and the state machine

`pipelines` keeps tenant-editable stages per record type and a stage
history. `state-machine` keeps the transitions a status may take, as the
caller, and it can derive its stages from a workflow version. A pipeline
already sets a status column from the stage category through the state
machine, so the layering exists in one direction. The decision is that
pipelines stay on top: they never own transition rules, and the state
machine never owns stage names.

Follow-up PR `feat/pipelines-on-state-machine`: when a record type has a
machine, a stage move runs through it, so a record has one history of
status changes, and the board reads the stage history from `pipelines`.

### The schedule engines

`reminders` expands RFC 5545 recurrence and `calendar` stores events that
use it. Both are about moments a person sees. `ai-schedules`, queue
schedules and workflow schedules are cron entries that start machine work,
each with a time zone and a next-run time.

Follow-up PR `refactor/shared-cron-helper`: one SQL helper that parses a cron
expression in a time zone and returns the next run, used by `ai-schedules`,
`queue` and `workflows`, with the same golden tests. No table is merged.

Done: the three engines already computed the next run in TypeScript, so the
helper (`nextCronRun`, `assertCron`) moved from the `queue` block into
`src/core/cron.ts`, with its tests. `better-supabase/queue` still exports both.

### The workflow family

The blocks form a stack and each layer has one job:

1. `automations`: one trigger, a filter tree and named actions.
2. `workflow-editor`: graphs that members edit and publish.
3. `workflows`: the run registry for any engine, including `workflow-sdk`.
4. `sequences`: outreach steps that run on `enrollments`.

Follow-up PR `feat/automation-start-workflow`: an `automations` action kind
that starts a published `workflow-editor` workflow, so a rule can hand over
to a graph without a custom action.

### The credential blocks

Inbound keys that others present (`api-keys`, `service-accounts`), keys the
app signs with (`signing-keys`), storage for an authorization server
(`oauth-server`), and secrets the app holds for third parties (`credentials`
and `ai-keys`, which already stores credential references) have different
owners, rotation rules and revocation paths. They stay apart and no code
moves.

### SSO domains and hostnames

`sso` verifies an email domain so people who sign in with it join an
organization. `domains` verifies a hostname the organization serves the app
on and answers the proxy's lookup. Both use a DNS TXT record, but they
verify different claims and are read by different callers. The two pages
each say so and link to the other.

### Docs groups

Seven blocks move to the group that matches their job. The URL of a block
page is `/docs/blocks/<name>` and the group folder is only a route group,
so no page URL changes and no redirect is needed. The manifest `category`
changes with the folder, because `scripts/docs-drift.ts` requires both to
agree.

| Block          | From          | To       |
| -------------- | ------------- | -------- |
| `incidents`    | developer     | work     |
| `assignment`   | crm           | work     |
| `enrollments`  | collaboration | people   |
| `lead-scoring` | growth        | crm      |
| `trash`        | content       | database |
| `versions`     | content       | database |
| `imports`      | content       | database |

## Alternatives considered

- Merge `collections` into `saved-views` (or the reverse). Rejected: one
  table would hold two kinds of row with different lifecycles.
- Fold the stage tables of `pipelines` into `state-machine`. Rejected: the
  state machine has no tenant-editable surface and no board totals.
- One `schedules` table for every engine. Rejected: the engines differ in
  who sees the result and what a run does, and a shared table would need a
  permission model for each.
- Merge the credential blocks into one `credentials` block. Rejected: the
  verbs differ (present, sign, store) and merging would put signing keys
  and third-party tokens behind one permission.
- Keep the docs groups. Rejected: a reader looking for incident handling
  would open the developer group.

## Consequences

Three follow-up PRs are accepted and not part of this change:
`feat/pipelines-on-state-machine`, `refactor/shared-cron-helper` and
`feat/automation-start-workflow`. The planned DAM block builds
brand collections on `collections` and does not wait for any of them. The
catalog groups the seven blocks differently, which is the only visible
change. Revisit the schedule decision if a fourth engine needs the shared
helper.
