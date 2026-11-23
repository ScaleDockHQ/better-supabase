# 1180: Claim only assigned tasks unless claims.next is "any"

- Status: accepted
- Date: 2026-11-22

## Context

`claim_next_task` ordered the caller's own tasks first and then took any ready task of the tenant, so a person or an agent session that called `claimNext` could pick up work somebody else was assigned. An agent acts with a member's access, so it could widen its own pick the same way. The pick orders by task `number`, not by creation time.

## Decision

`blocks.tasks.options.claims.next` is `"assigned"` (default) or `"any"`. With `"assigned"`, `claim_next_task` considers only tasks assigned to `auth.uid()`, and a `filter.assigneeId` that names someone else raises `TASK_FILTER_FORBIDDEN` (42501). With `"any"`, a person keeps the old order: assigned first, then the lowest number. A session whose JWT has `act.kind = 'agent'` is always restricted to its user's own tasks, under either value, and `claim_task` raises `TASK_NOT_ASSIGNED` (42501) for an agent claiming a task that is not assigned to its user. A person can still claim an unassigned task by id. The service role is never restricted. The default change is breaking and is called out in the 0.83 changeset and migration notes.

## Alternatives considered

Keeping `"any"` as the default and documenting the risk was rejected: the safe behavior has to be the one an adopter gets without reading. A per-call flag was rejected because an agent could set it.

## Consequences

Adopters who relied on a shared queue set `claims.next: "any"`. Agents cannot use `claimNext` as a shared queue under any option value.
