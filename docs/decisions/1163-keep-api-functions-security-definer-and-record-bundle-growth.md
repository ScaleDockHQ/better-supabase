# 1163: Keep API functions security definer and record the task bundle growth

- Status: accepted
- Date: 2026-11-21

## Context

The brief for ADRs 1110 to 1118 said API entry points should be `security invoker`. #1105 shipped them as `security definer` with `set search_path = ''` and explicit scope checks, and asked us to confirm which is right. #1105 also raised the Next.js server baselines by about 8.7 KB raw per route.

## Decision

The repository convention overrides the brief. Every block API function (`claim_task`, `hold_task`, `close_task` and the rest) is `security definer`, loads the row through the shared `load` helper and checks the permission with the caller's identity (`auth.uid()` and the scope helpers) before it writes, and refuses an agent that the `act` claim marks read-only. A definer function is needed because the tables are locked for direct writes (ADR 0104): an invoker function could not write them. The only invoker functions are labelling helpers such as `task_actor`, which read claims and write nothing. Functions that approvals or housekeeping call carry no grant.

For the bundle, the SQL generator is not in any runtime entry: no route's server bundle contains a `create or replace function` string, and `better-supabase/tasks` imports only the client chunk. The growth is the client code of `createTasks` (claims, holds, plans, outcomes and their decoders, about 25 KB of source before minifying) and the generated hint messages, which every route that imports a block client pays once in the shared chunk. That is the feature, so the baselines record it and no code moves.

## Alternatives considered

Switching the API to `security invoker` was rejected: it would need write policies for every coordination column, which weakens ADR 0104. Splitting the coordination methods into a lazy chunk was rejected for about 9 KB raw.

## Consequences

Baselines change only from CI's measured numbers, so the follow-up commit copies them in. A future change that puts SQL text in a runtime chunk fails the bundle check.
