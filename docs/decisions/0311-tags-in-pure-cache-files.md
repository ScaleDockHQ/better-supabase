# 0311: Keep tags in pure `<domain>-cache.ts` files built on `tagFor`

- Status: accepted
- Date: 2026-11-07
- Amends: 0310

## Context

The example app wrote three tag formats by hand (`teams:<org>`,
`permissions:<user>`, `permissions:organization:<org>`) and exported them from a
queries file, so an actions file imported a `server-only` module for a string.
A table write through the library invalidates `bsb:<table>` and
`bsb:<table>@<tenant>`, which the hand-written tags never matched.

## Decision

- Each feature that tags a read itself keeps its tags in a pure
  `<domain>-cache.ts` (`teams-cache.ts`, `user-cache.ts`, `billing-cache.ts`).
  Queries, actions and helpers import from it, and the file builds each tag with
  `tagFor` from `better-supabase/next`: `bsb:teams@<org>`,
  `bsb:permissions:<user>` and `bsb:permissions@<org>`.
- `scripts/check-app-architecture.ts` fails a `*-cache.ts` that imports
  `server-only`, `next/cache`, the server client or a `'use cache'` or `'use
  server'` directive.
- Reads that go through `bsb.cached({ tables })` keep the library's tags and the
  client query keys keep the generated `queries.<table>` factories, so the app
  writes no tag for them.

## Consequences

A write to a `teams` or `permissions` table through a repository expires these
entries as well as the explicit `updateTag` in the actions. Still open in the
library: nothing for tags; the cache life is ADR 0312.
