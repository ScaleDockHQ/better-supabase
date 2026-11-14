# 0922: Enforce the entity flag key through hooks

- Status: accepted
- Date: 2026-11-14

## Context

`EntitySurface.flag` named a feature flag key that was only documentation. Nothing hid the entity's methods when the flag was off, so each app wrote the same check by hand (EX-1328).

## Decision

An entity that sets `flag` also lists the block `methods` the flag hides. `createBlocks` takes `flags: (key) => boolean | Promise<boolean>` and merges one `before` hook per listed method, the same way it merges the metering hooks. While a flag is off the method returns a `not_found` `DbError` ("`<entity>` is not available") without calling the database. A check that throws counts as off. A method shared by several flagged entities needs every flag on. Without `flags`, nothing is enforced, so existing apps keep their behavior. The flag hooks run first, so a user's `before` hook never skips them.

## Alternatives considered

Hiding routes only in generated pages left the methods callable from actions and the browser. Reading a flag provider inside each block added a runtime dependency (invariant 1).

## Consequences

An app wires its provider once (`createBlocks({ flags })`) and every declared method follows. A test fails when an entity names a flag without `methods`. Routes still need the flag in the app's own navigation.
