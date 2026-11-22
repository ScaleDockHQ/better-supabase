# 1111: Create a plan of tasks in one call

- Status: accepted
- Date: 2026-11-21

## Context

An agent that decomposes work creates many tasks that name each other. Doing it one call at a time leaves half a plan when one call fails.

## Decision

`create_tasks` validates the whole plan, then writes it in one transaction; entries name each other by `key` in `parentId` and `needs`. At most 100 entries, with an optional idempotency key. The client method is `createPlan`, because `createMany` is a retired data-contract verb. The function is `security definer` with explicit `ctx.scope.can` checks, as the rest of the repo does; the brief's invoker was not used because the checks must read tables the caller can't.

## Alternatives considered

Several `create` calls inside a client transaction were rejected: the client has no transaction across transports.

## Consequences

One more entry point to keep in step with `create`.
