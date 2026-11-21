# 1117: Expose stage times and a live topic

- Status: accepted
- Date: 2026-11-21

## Context

Dashboards need time in stage and a signal to refetch.

## Decision

`task_stage_times` reads the pipeline history; the open stage counts up to now. A trigger broadcasts `{ id, change, table }` on the topic `tasks:{tenant}`; the payload has no entity words so `entity-renames` stays clean.

## Alternatives considered

Sending the row on the topic was rejected: the topic would bypass row policies.

## Consequences

Clients refetch on a message.
