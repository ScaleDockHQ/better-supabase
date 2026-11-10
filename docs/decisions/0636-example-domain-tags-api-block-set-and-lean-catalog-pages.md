# 0636: Tag every domain read, serve /api/v1 from an api block set and keep the catalog pages under 512 KB

- Status: accepted
- Date: 2026-11-10
- Amends: 0615

## Context

ADR 0615 moved four settings pages from session eviction to domain tags and left 25 action
files on eviction, because their reads carried no tags and the cross-domain readers (the
dashboard, my work, approvals, the invoice readers, trash) would have gone stale. The same
audit left `/api/v1` on the full block set, and the Vercel log reported one error group: the
`/recipes` (1,542,610 bytes) and `/blocks` (1,297,829 bytes) documents exceed 512 KB without
a Suspense boundary the browser could stream.

## Decision

- Every `'use cache: private'` read in a domain's `*-queries.ts` carries that domain's tag
  (`<domain>-cache.ts`, ADR 0311) and the tags of the domains whose rows it shows. Each action
  passes its own tag and the tags of the domains its writes change: `refreshCaller(auth,
  [CRM_TAG, CUSTOMERS_TAG])`. 31 action files moved (access requests, acknowledgements,
  approvals, banking, billing, bookings, calendar, cases, community, composites, courses, crm,
  custom fields, customers, drive, field, forms, imports, inspections, manufacturing, people,
  privacy, projects, rules, sequences, service principals, shop, teams, templates, work). The
  dashboard, my work, the customer list, care, medications, observations and warehouse reads
  carry the tags of the domains they read. `tests/lib/refresh-tags.test.ts` fails when an
  action file calls `refreshCaller(auth)` without tags or a domain read has no `cacheTag`.
- Roles, sessions and trash keep session eviction. Roles and sessions change what the caller
  is. A restore or purge changes every trashable domain, and the trash list is tagged with all of
  them, so one tagged write would not be enough the other way round. The user's own reads
  (`user`), the bench and the islands demo stay session reads.
- `gen.serverBlocks.api` (`permissions`, `teams`) builds `betterSupabaseApi` and `bsbApi`, and
  `/api/v1` uses them. Its table registry loads through `loadTables` (ADR 0611).
- The chat routes, the pipeline overview and the banking overview stay on the full set: a read
  set (`defineReadSet(betterSupabase, ..., { blocks: reads })`) is bound to the full app and
  to the `reads` object in `blocks.generated.ts`, which imports every block. A lean route needs
  `gen` to write `reads` into a module of its own (and per `serverBlocks` set) and
  `defineReadSet` to take a smaller app. That is a library change, recorded in the plan.
- Geist Mono no longer preloads (`preload: false`): it is used for code and figures only.
- `/blocks` and `/recipes` render the first two (blocks) or one (recipes) tile of each category,
  and a button loads the rest from the prerendered `/blocks/index.json` and `/recipes/index.json`.
  The search and the filters read the same documents on first focus, with a Skeleton while they
  load and an alert with Retry when they fail, so the lists are no longer client props. The
  sidebars drop the per-entry glyphs, which were 370 inline SVGs, and planned recipes are a line
  of text per category.

## Measured

`tests/next-build`, one `next build` of `origin/main` plus the fixes of PR 768 against this branch.

- `/api/v1/[...path]` server: 2,319,957 to 1,064,109 raw (-54.1%), 701,908 to 336,467 gzip,
  587,612 to 294,688 brotli.
- The other 102 routes that import a tagged read or action grow by 2 to 1,345 raw bytes (the
  `cacheTag` import and the tag modules), at most 548 gzip. First-load client JavaScript is
  unchanged on all 130 routes. The server baseline is replaced by the measured numbers.
- `/recipes` document: 1,542,610 to 415,757 bytes. `/blocks`: 1,297,829 to 479,543 bytes.
  Intermediate steps: the summary props and `MoreLinks` cut about 480 KB, the sidebar glyphs
  about 130 KB, the tile count the rest (blocks with six tiles per category: 724,581).

## Measured away

- `realtime/client` and lazy bucket upload code (p4-library): four routes carry the topic SQL
  builders (documents/[id], shop/kitchen, shop/kitchen/board, chat) in chunks of 12 to 20 KB
  gzip each. The builders are a fraction of those chunks, under 1% of a 450 KB gzip route.
  Not built.
- The duplicated not-found chunk is outside the first-load sum by the baseline's own rule
  (`SHARED_ENTRIES`); it was not changed.

## Not done

- The Vercel runtime-error group was not re-queried: the deployment is not part of this branch.
- Writes that change other domains' reads in ways this change did not trace stay stale until
  the entry's life ends. The relations are listed in each action file's tag list; extend the
  list when a read joins another domain's table.
