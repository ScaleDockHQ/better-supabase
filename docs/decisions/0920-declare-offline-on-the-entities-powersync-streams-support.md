# 0920: Declare offline on the entities PowerSync streams support

- Status: accepted
- Date: 2026-11-14

## Context

`EntitySurface.offline` existed and no manifest set it, so the capability matrix showed no offline entity while `better-supabase powersync streams` syncs eight blocks (ADR 0392, EX-1318). The list of supported blocks lived only in `POWERSYNC_BLOCKS`.

## Decision

The `notifications`, `attachments`, `memberships`, `teams`, `profiles`, `observations`, `medications` and `activities` manifests set `offline: true` on the entity the stream carries. `tests/blocks/entity-surface.test.ts` fails when the blocks that declare `offline` differ from `POWERSYNC_BLOCKS`, so a block cannot gain a stream without a declaration or declare one without a stream.

## Alternatives considered

Deriving `POWERSYNC_BLOCKS` from the manifests at runtime loses the literal union that types `PowerSyncBlock`, and each block's stream query still needs its own columns and filters.

## Consequences

The matrix lists the offline entities. The per-block stream queries stay hand-written, so generating a stream for a new block from the declaration alone is not done: it needs the column and tenant rules each block states in SQL.
