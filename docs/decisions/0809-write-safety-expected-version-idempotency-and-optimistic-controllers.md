# 0809: Write safety: expected version, idempotency keys and optimistic controllers

- Status: accepted
- Date: 2026-11-13

## Context

The block consistency audit found that fewer than ten blocks refuse a stale update, so
everything else is last writer wins (EX-1213). 19 blocks accept an idempotency key and
`tasks.create`, `deals.create` and `quotes.create` do not (EX-1212). No block controller
exposes an optimistic update, although `useOptimisticAction` exists (EX-1214, ADR 0631).
Entities declare how they change since ADR 0689, so write safety can follow the
declaration.

## Decision

- **`STALE_WRITE`.** An update that carries `expectedVersion` (the row's `updatedAt` as
  the caller read it) compares it inside the write's transaction, on the locked row, and
  raises the hint `STALE_WRITE` with the SQLSTATE `BS409`. `mapDbError` maps that code to
  a `conflict` error (status 409), `toProblem` answers it with its own type
  (`.../problems/stale-write`), and `isStaleWrite` tells it from a unique violation.
  A batch compares every change of one item to the row as it was before the batch, so
  two changes to one item never refuse each other. `strictChanges` returns the refusal
  as a `conflict`. The constants live in `src/core/stale-write.ts`.
- **`idempotencyKey`.** `idempotentCall` (`src/core/idempotent-write.ts`) claims a key
  through the idempotency block's `begin`, `complete` and `release`, around the raw
  response of the RPC, so a replay decodes the stored value with the same decoder as a
  fresh call. A block takes the claims as its `idempotency` option. Keys are scoped to
  the organization and fingerprinted by call name and arguments.
- **Optimistic controllers.** `createBlockMutation` and the four `useBlockMutation`
  hooks take `optimistic`, a list of cached reads and an `apply` function. It rewrites
  the engine's reads before the call and puts them back when the call fails.
  `optimisticUpdate`, `optimisticArchive` and `optimisticReorder` build the common ones
  for a cached list or page. Every block controller is this one function, so every block
  gets it; there is no per-block handler to write.
- **Declaration.** `EntitySurface` gains `expectedVersion` and `idempotent` (the methods
  that take a key). `tests/blocks/write-safety-gaps.ts` lists the editable entities
  without `expectedVersion` and the entities whose `create` takes no key, and
  `write-safety.test.ts` fails on any entity missing from the lists or listed after it
  was fixed. Like `emit-gaps.ts`, the lists only shrink.

This PR applies the guard and the key to `tasks` (`update` with `expectedVersion`,
`create`), `deals` (the same) and `quotes` (`create`). The remaining entities are on the
gap lists, to roll out by category in follow-ups.

## Alternatives considered

- A check in the client (read, compare, write): not atomic, so two writers both pass it.
- `expectedVersion` as an integer `version` column on every table: needs a migration of
  every table; `updatedAt` is on all of them and the audit's blocks already use it
  (`expectedUpdatedAt` in `employees`).
- Storing the idempotent response as JSON of the decoded value: Temporal values and
  bigints don't round-trip, so the raw RPC value is stored instead.

## Consequences

`employees` keeps `expectedUpdatedAt` (`EMPLOYEE_STALE`), and `memory` and `ai-files`
keep their integer `expectedVersion`; renaming them is breaking and is listed in the
gaps. The manifest fields grow the server chunk, so the server baselines are reset
(ADR 0690). A create that sets custom values after the insert re-runs the values on a
replay; they are idempotent writes.

The next-build first-load and server baselines were reset to the measured numbers of a fresh
`next build` (emptied, then updated), as in ADR 0690. `supabase/snapshot.json` needs
`pnpm supabase:reset` and `gen --save-snapshot` on a running stack.
