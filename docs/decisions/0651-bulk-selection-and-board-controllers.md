# 0651: Add a bulk selection controller and a board lane controller

- Status: accepted
- Date: 2026-11-10
- Amends: 0030

## Context

ADR 0030 keeps block client state in headless controllers. `bulk-actions` and `pipelines` had none, so
every table with a checkbox column and every board rebuilt the selection, the pending flag, the
optimistic move and the rollback. `p5b-next-rest` listed both controllers. It also listed batch block
reads: those already run through read sets (`s.blocks.*` inside `db.$many`), which batch function
specs into one call, so nothing is added there.

## Decision

- `createBulkSelectionController({ run, watch? })` in `better-supabase/blocks/bulk-actions` holds the
  selected ids and runs an action on them through the app's `run`. A run that succeeded for every row
  clears the selection; failures stay selected for a retry. `watch` follows a background run and is
  cleaned up with the controller.
- `createBoardController({ lanes, move })` in `better-supabase/blocks/pipelines` moves a card in the
  lanes at once, calls `move`, and restores the lanes when the call throws, unless the lanes changed
  again since (then `error` tells the app to refetch).
- Both use `defineController`, so every framework runs them with `useBlockController`. No React hook
  registry item is added; the registry is generated and the hooks are one line.

## Alternatives considered

- A move that waits for the server: the board would lag behind the drag.
- Rolling back by replaying later moves: the server order is unknown, so `setLanes` after a refetch is
  the safe fix.

## Consequences

Two new exports per block entry and their types. The entries already exist, so no subpath or tsdown change. The size baseline of `./blocks/bulk-actions` rises from 27,077 to
28,695 bytes gzip (the controller runtime joins the entry); `./blocks/pipelines` stays within its baseline.
