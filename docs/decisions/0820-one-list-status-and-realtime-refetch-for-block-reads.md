# 0820: One list status and realtime refetch for block reads

- Status: accepted
- Date: 2026-11-13

## Context

Block read hooks return the query state (`idle`, `loading`, `success`, `error`
with `data`), so every list decides for itself what an empty or failed read
shows (EX-1326). An entity can declare `realtime` in its manifest (ADR 0689), but
no hook reads it (EX-1319).

## Decision

`blockListStatus(state)` maps a read's state to `BlockListStatus<Row>`:
`loading`, `empty`, `error` or `ready`. `blockRealtimeRefetch(block, entity,
source)` returns the `refetchOn` of a read when the entity declares `realtime:
true`, using the block events that start with `<entity>.` or, when none does,
every event of the block. Both live in `src/blocks/block-list-status.ts`, import
no framework, and are exported from the React, Vue, Svelte and Solid entries.

## Alternatives considered

A separate `useBlockList` hook per framework would repeat the logic four times.
Subscribing through Supabase Realtime channels directly needs a topic per
entity; block events already reach clients through the event hub the hooks use.

## Consequences

Lists and the record list kit read one status. No entity declares `realtime`
yet, so no list subscribes until the owning lanes set it.
