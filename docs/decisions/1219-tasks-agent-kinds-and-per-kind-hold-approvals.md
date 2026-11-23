# 1219: Name the agent session kinds and approve each hold kind on its own

- Status: accepted
- Date: 2026-11-23

## Context

The tasks block treats a session as an agent only when its `act` claim has
the kind `agent`. The claim rules narrow an agent: it claims only tasks
assigned to its user, `claimNext` never widens the pick, and it can't take over
a task reserved for a profile. An MCP client (a token with `client_id`, or an
`act` claim without a kind) and an app API key (`api_key`) passed as a person,
so each could claim an unassigned task by id and take over a reserved one. An
app that wanted them narrowed had to repeat the rules in its own route.

`options.hold.approval` had one policy and one `onReject` for every approvable
hold kind, so a spend hold and a review hold could not file under different
approvers or settle a rejection differently. The list had a `ready` filter but
no filter for the tasks that still wait on a prerequisite, so apps filtered on
`waiting_on` themselves.

## Decision

`options.claims.agents` lists the session kinds the claim rules treat as
agents: `"agent"`, `"oauth-client"` and `"api-key"`. `"agent"` always counts,
so the default (`["agent"]`) renders the same SQL as before. The rendered test
is an `or` of one JWT check per kind, in `tasks-coordination-claims.ts`, and
drives the three guards: `TASK_NOT_ASSIGNED`, the assigned-only `claimNext` and
`TASK_RESERVED`.

`options.hold.approval.kinds` also takes a record from hold kind to `true` or
`{ policy, onReject }`. A field the entry leaves out comes from the block-wide
option. `hold_task` files the request under the kind's policy. When the kinds
disagree on `onReject`, the approvals reject hook passes `'reject'` to
`settle_task_hold`, which reads the task's `hold_kind` and cancels or keeps the
hold. When they agree, the SQL is the same as with one rule. The record needs
the `hold_kind` column.

`page_tasks` gains a `waiting` filter: open tasks with `waiting_on > 0`. The
module moves to version 8 with an upgrade step that adds no SQL to an existing
install.

## Alternatives considered

Narrowing MCP clients and API keys in each app's route works, but every app
repeats it, and a direct PostgREST call skips it. Treating every non-interactive
session as an agent by default would change who can claim what in existing
apps without a config change. A separate approvals subject type per hold kind
would split one task's requests across subjects and change the event payloads.

## Consequences

An app opts MCP clients and API keys into the agent rules with one option. A
mixed `onReject` record adds a branch on `hold_kind` to `settle_task_hold`,
and a hold kind that later changes its `onReject` applies to requests already
pending. A new session kind needs a new entry in `AGENT_KINDS` and its JWT
check.
