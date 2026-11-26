# 1254: Actions expire tags and refresh

- Status: accepted
- Date: 2026-11-26

## Context

`bsb.action` expired the tags of the tables in `invalidates`. An action that
changed a tenant-scoped tag or a row tag had to call `updateTag` itself, and
every caller refreshed the router after the call. The example app wraps actions
with `refreshCaller` at 383 call sites, and CentraKit calls `updateTag` 402
times.

## Decision

`ActionOptions` gains `tags(scope)` and `refresh`. After a successful call the
library expires the tags `tags` returns for the tenant, the validated input and
the data, in the same way as `invalidates`, and calls `refresh()` from
`next/cache` when `refresh` is true. A failed call does neither. The effects
live in `src/next/action-effects.ts`.

## Not in this decision

The app-wide `actions` option (`result`, `guard`, `from`), the generated tag
functions per table, the client `useAction` envelope and `TenantProvider` are
deferred. Each needs the generator and the React entry, and ships with its own
ADR.

## Consequences

An action can drop its manual `updateTag` and `refresh` calls today. Existing
`invalidates` keeps its behavior.
