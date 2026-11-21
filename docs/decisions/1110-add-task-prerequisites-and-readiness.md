# 1110: Add task prerequisites and readiness from blocks relations

- Status: accepted
- Date: 2026-11-21

## Context

A queue worker needs to know which tasks nothing blocks. The relations block already stores `blocks` edges, and its default kinds include `blocks`, so no new relation kind is needed.

## Decision

`options.needs: { kind: "blocks" }` adds a `waiting_on` count that triggers keep in step with the open prerequisites, a `ready` list filter, `setNeeds` and `create({ needs })`. The event is `task.unblocked`: `check:naming` requires a past-tense verb, and `task.ready` is an adjective. A canceled or failed prerequisite keeps its dependents blocked, because the work it stood for did not happen. Deleting a prerequisite readies its dependents, because the edge disappears with it. Setting needs takes the relations manage permission and refuses a prerequisite of another tenant. The columns exist only when mapped, so an adopted table works unchanged.

## Alternatives considered

Counting on the read path (a view) was rejected: the claim path locks rows and needs a column.

## Consequences

Adopters get one more column to map. Dependents of a failed prerequisite need a manual decision.
