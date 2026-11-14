# 0902: Declare which entities keep history

- Status: accepted
- Date: 2026-11-14

## Context

`versions` and `field-history` exist, and no manifest says which entities keep
history, so a page cannot show a history tab by declaration (EX-1323).

## Decision

`EntitySurface.history` is `true` or the columns whose changes the
`field-history` block keeps. `historyTabs(blocks)` in
`better-supabase/blocks/field-history` lists them. The conformance test keeps the
flag off append-only entities, which are history themselves.

## Alternatives considered

Probing the database for a field-history binding at render time: it costs a
query per page and cannot be checked in CI.

## Consequences

Pages and the generator read the declaration. No shipped entity declares it
yet; record entities add it with their bindings in lane I.
