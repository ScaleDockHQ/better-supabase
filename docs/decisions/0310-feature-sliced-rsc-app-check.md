# 0310: Check the example app's feature-sliced RSC architecture in `pnpm verify`

- Status: accepted
- Date: 2026-11-07

## Context

The audit of `apps/examples/nextjs/src` found 16 pages that import a
`*-queries` file and define data components inline, 3 pages that `await
params`, 33 features that took the raw `params` or `searchParams` promise as a
prop, 36 queries and actions files named differently from their folder, 11
queries files without `import "server-only"`, and 12 components that called
`connection()` in render. The shape is the one of the `nextjs-app-architecture`
skill, and nothing kept it from drifting again.

## Decision

- `scripts/check-app-architecture.ts` runs in `pnpm verify` as
  `check:app-architecture` over `apps/examples/nextjs/src`. It fails when a page
  or layout imports a `*-queries` file, is `async` or awaits `params`; when a
  feature has a prop named `params` or `searchParams`; when a `*-queries.ts`
  does not import `server-only` or a `*-actions.ts` does not start with `'use
  server'`; when the file prefix differs from the folder; when an async
  component in `components/` has neither a `*Skeleton` in the same file nor a
  `// skeleton: <reason>` comment above it; when a feature renders `<Suspense>`
  outside the composite sections listed in the allow file; when `connection()`
  has no comment; and when a `'use client'` file imports an async server
  component.
- `scripts/app-architecture-allow.json` lists composite sections that nest
  sibling boundaries (with the reason) and the findings still open. The check
  fails when an entry stops matching, so the list only shrinks.
- Pages stay synchronous: a feature receives plain ids and a `query` object,
  resolved at the page with `params.then()` or `searchParams.then()`. The 16
  pages move their data components to `features/<domain>/components/*-section.tsx`.
  `scopeVariant`, `islandScope` and `SCOPE_COUNT` move to pure
  `<domain>-cache.ts` files so no page imports a queries file.
- `connection()` in feature components becomes `io()` from `next/cache`, which
  marks a clock or random read as I/O without blocking a prefetch.
  `app/api/bs-sessions/route.ts` keeps `connection()` with its reason.
- The app header takes its breadcrumbs as a slot, so the `(app)` layout owns the
  boundary.

## Alternatives considered

A lint rule in oxlint cannot see the file name against the folder or the sibling
skeleton, so a repository script is the smaller tool. Merging every second
queries or actions file into the folder's file in the same change would have
touched 13 more files and their callers; those stay in the allow list.

## Consequences

The example stays a template the `init` fixture can copy. The allow file lists
`roots` (the example app) and `pendingRoots` (`tests/init-fixture/nextjs/src`,
checked as soon as it exists), and `node scripts/check-app-architecture.ts
<root>` checks one path. The sub-concept files, the section skeletons, the tag
contracts, the cache lives, the prefetch gates, the `instant` tests and the
interaction fixes are ADR 0311 to 0315. The library work is specified in
`docs/agents/nextjs.md` (ADR 0316).
