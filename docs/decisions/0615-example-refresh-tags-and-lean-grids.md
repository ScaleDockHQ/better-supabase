# 0615: Expire domain tags after a write, and give display-only grids a lean feature bundle

- Status: accepted
- Date: 2026-11-10
- Amends: 0311, 0542

## Context

`refreshCaller` expired the caller's whole session after every write, so each action re-rendered
every page's `'use cache: private'` entries. Every data grid shipped the full TanStack bundle
(sorting, filtering, faceting, pagination, the six sort functions) although 20 of the 21 grids only
display rows. The route handlers, the OpenAPI document and the OAuth metadata route imported the
full block set for work that needs the core blocks or none.

## Decision

- `refreshCaller(auth, tags?)`. With tags it runs `updateTag` on each and then `refresh()`. Without
  tags it expires the session as before. A domain moves over by keeping its tag in a pure
  `<domain>-cache.ts` (ADR 0311), adding `cacheTag` to each read its writes change, and passing the
  tag from every action. This change moves four settings pages whose reads no other page shares:
  sso, webhooks, signing keys and jobs. Billing, banking, the shop, projects and every other domain
  stay on eviction until each of their cross-domain readers (the dashboard, my work, search, the
  invoices) carries the same tag. Membership, role and profile changes keep `evictSession`.
- `readOnlyGridFeatures` (`data-grid-features-read-only.ts`) registers the features the grid needs to
  render and size columns, without sorting, filtering, faceting or pagination row models and sort
  functions. `dataGridFeatures` moved to its own module (`data-grid-features.ts`) so a route that
  imports only the lean bundle does not carry the full one. The 20 display-only grids use the lean
  bundle; the task grid keeps the full one. A test renders both bundles to the same markup.
- The OpenAPI document builds on the core block set (`blocks: false` already). The OAuth metadata
  route builds `createMcp` over the core set with no tools, because the metadata depends on the
  request URL and the project, not on the tools. The customers list, customer by id, projects and
  session-status routes use `bsbCore`. `bsbShell` shares the session counters with `bsb`, so
  `/api/bs-sessions` counts both.
- Customers facets count in the capped mode (`facetCountMode: "capped"`, ADR 0425) and the status
  badges show a lower bound (`12+`) when the scan cap was reached.
- The access requests, sso, calendar, order detail and kitchen pages start their reads in the same
  wave as `getPermissions()` and refuse afterwards. The read helpers never reject, so a refused
  caller leaves no unhandled promise.

## Measured

Server-baseline and first-load baseline from `tests/next-build`, one `next build` before and after.

- The 21 pages with a display-only grid lose 10,860 raw bytes, about 2,320 gzip and 1,950 brotli
  each of first-load JavaScript (appraisals 1,468,898 to 1,458,038 raw). `/projects` grows by
  2,788 raw, 1,610 gzip and 1,443 brotli: it keeps the full bundle and now imports it as a module of
  its own. Its baseline is raised by hand to that number.
- Server chunks grow by 86 raw bytes on pages that import `refreshCaller` (the `updateTag` import),
  and by 167 to 285 on the four moved pages (`cacheTag`). The route handlers grow by 27 to 150 raw
  bytes from re-chunking. These baselines are raised to the new numbers.

## Measured away

- A dynamic `import()` for `wakeOnApproval` and the drive text extractor in `/api/outbox`, and for
  the shell server inside `flags.ts` (so the flags discovery route skips it), grew every route
  handler by about 1,300 raw bytes (5,500 gzip in the sum) and every page by about 1,600 brotli.
  The first dynamic import in a server module adds the async chunk loader to the runtime of each
  route that bundles it. Both were reverted: static imports stay.
- The `better-supabase/realtime/client` entry and lazy bucket upload code (p4-library): the topic
  SQL builders (`access-sql`, `topic-sql`, `topic-trigger`) are about 33 KB unminified, roughly 3
  KB gzip on routes of 450 KB gzip, and split a 1,400-line `defineTopic` and a new subpath. Not
  built; revisit with a measured bundle of a route that imports `defineTopic`.

## Not done

- Parties read by id and the batch block reads (assistant run steps, project versions, hiring
  applications, templates, care plans) need new SQL functions in the blocks, a regenerated fixture
  and pgTAP tests. The remaining `.map(...)` sites are parallel, not sequential, so only
  `loadContact` waits on up to ten pages. This belongs with the library's SQL changes.
- The remaining 25 action files keep eviction, for the reason above.
- `/api/chat`, the pipelines and banking overview routes and `/api/v1` stay on the full block set:
  the chat tools, the read sets (`reads` from `blocks.generated.ts`) and the teams and roles
  resources need blocks outside the core set.
