# Next.js in docs, marketing and the example

Both apps build on `createNextConfig()` from `packages/next-config`, with Cache
Components, typed routes and the security headers. Read
`node_modules/next/dist/docs` for the installed version before you change a
flag.

## Cache Components

- Segment configs (`export const revalidate` and `export const dynamic`) fail
  the build. Cache data with `"use cache"` and `cacheLife("max")` in the
  function that loads it.
- `Date.now()`, `Math.random()` and `new Date()` outside a cached function
  fail the prerender. Shiki reads the clock, so highlight inside a cached
  function (`components/code-block.tsx` in marketing).
- A client hook that creates an id on mount (`useChat`) fails the prerender
  as well. Mount the component only after user interaction, as `ChatPanel`
  (`apps/docs/components/chat-panel.tsx`) does; `ask-ai.tsx` loads it with
  `next/dynamic` and `ssr: false`, so its client code stays out of the page.
- `experimental.globalNotFound` needs `app/global-not-found.tsx` with its own
  `<html>`, fonts and `metadataBase`. Next serves it only when routing
  matches nothing; a `notFound()` in a root layout renders Next's built-in
  404 instead. An app with a dynamic root segment (the example's `[locale]`)
  never reaches it, so the example turns the flag off and answers unknown
  paths from `[locale]/[...rest]`, `[locale]/not-found.tsx` and
  `app/api/[...rest]/route.ts`.
- Outside a Vercel production build, `BSB_BUILD_SCOPE` is `minimal` and every
  `generateStaticParams` in docs and marketing returns its first 3 entries
  through `scopeStaticParams` (ADR 0109). Wrap a new one the same way, and
  run `BSB_BUILD_SCOPE=full pnpm build` to prerender every page. The scope
  is read from the shell env, not from `.env` files.

## Instant navigation

- Build `packages/better-supabase` first in a fresh worktree, and again after
  every library change: the example imports its `dist`, so a stale `dist`
  builds the example against the old code.
- A shared `"use cache"` read that uses `bsb.admin()` must sit behind a
  session read, or the build prerenders it and fails without
  `SUPABASE_SECRET_KEY`.
- Routes you left stay mounted in a hidden `<Activity>`, and a streamed
  Suspense boundary sits in a hidden `<div>` for a moment, so the same id,
  label or text can exist twice. Use `useId()` for form ids instead of fixed
  strings.
- Content that reads `params` can't be in the route's shared App Shell. A
  link to such a page needs `prefetch` to resolve its cached reads before
  the click (the customer rows in `customer-table.tsx`).
- Data a client component fetches in `useEffect` is never in the prefetch,
  so an `instant` page that does it shows a skeleton on every click. Load it
  in a `"use cache: private"` function with `bsb.cached()` and pass it in as a
  prop (`user-queries.ts` for the two-factor and connected agents cards).
  `supabase.auth` is off on the server client, which passes `accessToken`, so
  those reads call the Auth REST endpoints with `auth.token`.
- A database budget (`maxCalls`, `maxWaves`) fails on a navigation served
  entirely from the client cache, because no response carries
  `x-bsb-request-id`. Budget only navigations that reach the server.
- Don't export `instant = true`. With `instantInsights.validationLevel`
  at `warning` (the default), Next validates every page for an instant
  navigation already; the export only adds noise. Export `instant = false`
  with a reason on a segment that may block.
- `ensureStatic` levels only tighten down the tree: a page can't set
  `"shell"` under a layout that says `"prefetch"`. The example sets
  `"shell"` on the `(app)` layout and `"prefetch"` on the list pages.
- `instant()` from `@next/playwright` is a no-op under `next dev` and in a
  build without `EXPOSE_TESTING_API=1`, so its tests pass without testing
  anything there. `pnpm test:e2e` in the example builds with the flag and
  runs `next start`; it needs the local stack and is not part of `verify`.

## Write refresh

- A write calls `refreshCaller(auth, [DOMAIN_TAG, ...])` (ADR 0615, 0636). Every
  `'use cache: private'` read of a domain calls `cacheTag` with its own tag and the
  tags of every domain whose rows it shows, so a new read that joins another
  domain's table needs that table's tag too. `tests/lib/refresh-tags.test.ts`
  checks the two sides. Only roles, sessions and trash call `refreshCaller(auth)`
  with no tags, because they change what every read shows.

## Offline and PWA

- The example has one service worker, `public/sw.js`, for push and the
  offline shell. Register it only at `/sw.js`: a second URL in the same scope
  replaces the first worker and drops its push subscription.
- The worker stores nothing whose `Cache-Control` says `private` or
  `no-store`, and never replays a `POST`; `experimental.useOffline` retries
  Server Actions. Don't add a cache rule that bypasses that check.
- `/_next/static` is cache first in its own cache, trimmed to 512 entries and
  never cleared on a deploy (ADR 0840). It skips `/_next/static/service-worker/`,
  which Next.js serves with `must-revalidate`, and stores only responses whose
  `Cache-Control` includes `immutable`. Don't merge it into the shell cache or
  switch it to stale-while-revalidate.
- `/sw.js` gets `no-cache` and `Service-Worker-Allowed` from
  `createNextConfig()`. The proxy matcher skips `html` and `webmanifest`, or
  it redirects `offline.html` to the sign-in page.
- The registrar skips `next dev`, so test offline behavior with `next build`
  and `next start`.

## Lint needs generated Next types

`PageProps<Route>` and `next/root-params` come from `next typegen` (`.next/types`).
The example `lint` script runs typegen first so type-aware Oxlint has them on a
clean CI checkout. Local `next dev` leaves those files around, which hid the
gap. Docs and marketing do not use those names, so their `lint` stays `oxlint`.

`withWorkflow` (`workflow/next`) bundles the workflow files with esbuild
when `next typegen` loads the config, and that bundle resolves
`better-supabase` through the published `dist` exports, not the source
condition. So `lint` and `typecheck` in the nextjs and eve examples
depend on `^build` as well as `transit`; without it, a CI run with no remote
cache fails with `Could not resolve "better-supabase/blocks/..."`.

## The example app

- Library code imports `next/navigation` by its bare specifier. Next aliases
  it to the react-server build only without the `.js` suffix; with it, every
  route handler that imports `better-supabase/next` fails the build with
  `MODULE_UNPARSABLE` on the app router context.
- `useAction` callbacks written as expression arrows
  (`onSuccess: () => toast(...)`) return the toast id and fail Oxlint's
  `strict-void-return`; give them a block body.
- `protect` in `src/proxy.ts` runs on GET and HEAD only. Server Actions post
  to the current URL, and a guest-only redirect on that POST breaks sign-in.
- `refresh()` from a Server Action doesn't evict prefetched private App
  Shells. After the session changes (sign-in, organization switch), call
  `router.refresh()` on the client after `router.push`; `useSessionChange`
  does both (`use-refresh-session.ts`), and don't link to a page whose signed-out
  prefetch is a redirect (the brand in the auth layout).
- next-intl reads `.po` catalogs keyed by `msgctxt` only with the header
  `X-Message-Key: msgctxt`; without it the keys are dropped and every message
  is missing.
- A shadcn `Button` with `render={<Link />}` gives the link `role="button"`.
  Style the link with `buttonVariants()` instead.
- `Math.random()` during render fails the prerender, including skeleton
  widths; use a fixed list.
- next-intl's `Link` and `useRouter` take a plain string, so they bypass
  `typedRoutes`. The example wraps them in `src/i18n/navigation.tsx` with
  `Route` hrefs; import navigation from there, never from `next-intl`.
- `typedEnv` writes `.next/dev/types/env.d.ts` only in `next dev`, and it
  declares only the keys in local env files. Once it exists, Oxlint's
  `dot-notation` flags `process.env["KEY"]` for those keys, while a clean
  checkout flags nothing. Destructure `process.env` (`env.ts`) so both
  pass.
- Turbopack constant-folds `const s = "pkg"; import(s)` into a static
  import and tries to resolve the package, even inside code that never
  runs in the app (the testing entry through `instrumentation.ts`).
  Library code loads optional peers through `importOptionalPeer`
  (`src/core/optional-peer.ts`).
- data-grid cells must be top-level components. Pass handlers through a
  context whose value is `useMemo` over `useCallback`s, and put per-row
  flags (`removable`, `busy`) in the row data
  (`features/members/components/member-table.tsx`). Inline cell renderers,
  context values built in render and fresh functions in deps all fail
  Oxlint.
- A dynamic `import()` in a server module adds the async chunk loader to every
  route that bundles it: one in `/api/outbox` and one in `flags.ts` grew every
  route handler by about 1.3 KB raw. Measure `tests/next-build` before you
  lazy-load server code (ADR 0615).
- A grid that only displays rows uses `readOnlyGridFeatures`
  (`data-grid-features-read-only.ts`); the full `dataGridFeatures` lives in its
  own module, so import it only where a grid sorts, filters, pages or selects.
- The commit hook runs `ultracite fix` on the staged files, and it fails
  with "No files found" when every staged file is lint-ignored (generated
  clients alone). Commit generated files with the change that needs them.
- After `git mv`, stage the edited file again: the hook lints the staged
  content, not the working tree.
- The token hook writes the active tenant's permission keys into the
  `permissions` claim, so the proxy answers a gated page with the 403 page
  before rendering, with no database read. A token over the 2048-byte budget (measured as the token carries it,
  without the spaces `jsonb` prints; an owner is 2,040 bytes, a member stays over)
  carries `permissions_truncated` and no keys; the proxy lets it through and
  `getPermissions()` falls back to `my_permissions`. Don't gate pages from a
  client component after render; that was `PermissionRedirect`, and it showed
  the page before it left.
- Auth placement: the proxy refreshes the session and answers coarse checks
  (signed in, page permission). Server Components read the verified claims
  and never refresh. Actions and route handlers check again with
  `permission:` (the `permissionsAuthorizer`), because they can be called
  without a page. `next-auth.mdx` maps this onto the Next.js authentication
  guide (DAL, DTOs, optimistic checks); keep the two in step.
- Start a private read together with `getPermissions()` instead of after it.
  Two reads in a row keep the response open for two round trips, and Chrome
  holds a reload of the same URL until that response ends (its HTTP cache
  lock), so a reload looks slow even when the server answers at once.

## Islands, bootstrap and the remote scope

- `/islands` sits outside the `(app)` layout on purpose: the sidebar and
  menus there make their own calls, so the page's budget (one token
  verification, one `bootstrap_islands` call) would fail. Keep new budget
  pages outside it too.
- `bsb.bootstrap()` calls the wrapper in the schema `gen` records for the
  sessions block (`meta.bootstrap.schema`: its `api`, then `sql.api`), so the
  example reaches `api.bootstrap_islands` without options. Run `gen` after
  changing the sessions block's `api` or `schema`, or the call keeps the old
  schema.
- A verification is a session memo miss. The e2e test reads the counts from
  `/api/bs-sessions` (`bsb.sessions.stats()`), which answers only in a build
  with `EXPOSE_TESTING_API=1`.
- Without `cacheHandlers.remote`, each `next start` keeps its own remote
  entries. The example points `remoteCacheHandler` at a file store when
  `BSB_REMOTE_CACHE_DIR` is set; only the tests set it.
- Realtime doesn't replay a broadcast sent before the channel joined. A test
  that bumps the authorization version waits for the `phx_reply` with status
  `ok` to the `realtime:authz:<uid>` join first (`authzJoined` in
  `tests/islands.spec.ts`).

## API and MCP in the example

- `src/features/api/api-resources.ts` is the one resource map: `/api/v1`
  serves it (`bsb.resources`) and `/api/v1/openapi.json` renders it
  (`createOpenApi`). Check the map with `satisfies Parameters<typeof
  bsb.resources>[0]`; a resource with only `select` then fails TypeScript's
  weak-type check against the spec's `ResourceDescription`, so give it
  `operations`.
- `bsb.resources` serves models only. Block tables in `better_supabase`
  (teams, catalog roles) are actions on `organizations`, and an action sees
  only `{ id }` from the path.
- Type an action's `data` with `defineAction` from `better-supabase/next`.
  With an explicit `Db` type argument, pass the input schema's type as well
  (`defineAction<Db, string, typeof Input>`); TypeScript doesn't infer the
  rest.
- The OpenAPI document ignores `select` and describes every column, and a
  tag's description is the raw table comment, `@bsb` tags included.
- The permissions block ships no `Authorizer`, so an MCP tool or action
  `permission` is hidden and refused. The example's override tool relies on
  `set_permission_override`, which refuses without `roles.manage`; the tool
  returns that as a tool error.
- An MCP tool that returns an array gets no `structuredContent`; clients
  read the JSON from `content[0].text`.
- The proxy matcher skips `/.well-known/oauth-protected-resource`, or
  next-intl prefixes it with a locale and the metadata route answers 404.

## Routes and env

- Docs routes live under `/docs` (`/docs/og`, `/docs/api/chat`), because
  Vercel Services sends only `/docs/*` to the docs app. A new route outside
  `/docs` needs a rewrite in `vercel.json`.
- `typedRoutes` rejects a plain `string` href. Narrow it with a type guard
  that returns `href is Route` (`isAppRoute` in `components/site/site-link.tsx`).
- Read env through the app's `env.ts`, never `process.env`. A key the build
  reads goes into the app's `turbo.json` `env` list.

## Fumadocs

- `lastModified: true` goes on `defineDocs` in `lib/source.ts`; the plugin in
  `source.config.ts` alone does not set `page.data.lastModified`. On Vercel,
  set `VERCEL_DEEP_CLONE=true` so the dates come from git.
- The AutoTypeTable remark plugin resolves `path` from the repo root
  (`basePath: "../.."`).
- The docs page sits in a Suspense boundary under Cache Components, so
  `notFound()` there streams a 200. `proxy.ts` answers unknown `/docs` URLs
  with a 404 instead, from `lib/page-slugs.json`. `build` and `dev` write that
  file (`scripts/page-slugs.ts`); `generateStaticParams` throws when it drifts
  from the source, and a test checks it. Commit it after adding a page.
- Markdown for agents (`.md`, `llms*.txt`, `/mcp`, Ask AI) goes through
  `docsLlms` in `lib/source.ts`, which renders MDX components with their
  Markdown forms in `components/mdx-markdown.tsx`. A component without one
  prints as JSX in `llms-full.txt`; add its form there.
- Next drops `Vary: Accept` from prerendered HTML pages even when the proxy
  sets it; the Markdown rewrite keeps it.
- Keep the `Accept` negotiation in `proxy.ts`. A `has` header rule in
  `rewrites()` can't compare q-values the way `isMarkdownPreferred` does, and
  the proxy runs on every docs URL for the 404 check anyway.
- Load agent Markdown through the `"use cache"` functions in `lib/source.ts`
  (`getLLMIndex`, `getFullMarkdown`, `getPageMarkdown`), so the build
  prerenders the routes and `/mcp` and Ask AI reuse the rendered pages.

## Images under Vercel Services

The marketing app sets `images: { unoptimized: true }`. In production,
Vercel Services rewrites `/_next/(.*)` to the marketing service, and the
image optimizer doesn't answer through that rewrite: `/_next/image?url=...`
returns 404 while the file under `public/` returns 200. Serve images from
`public/` at the size they are shown, and check a new image with `curl -I`
against production after the deploy.

## Flags SDK in the example

- `precompute` in the proxy reads the original request's cookies, so a
  cookie the proxy sets (the `visitor-id`) only counts from the next request.
- With Cache Components, `generateStaticParams` can't return `[]`; the
  pricing page returns one `default` code when `FLAGS_SECRET` is unset.
- Pass the adapter itself (`adapter: bsFlags`) and put `identify` on
  `createBetterSupabaseAdapter`, not on each flag.

## App architecture

`pnpm check:app-architecture` holds the example to the feature-sliced RSC rules
(ADR 0310). Pages compose: they import feature components and place
`<Suspense>`, stay synchronous and turn `params` or `searchParams` into plain
values with `params.then()` before a feature sees them. A feature takes ids and
a `query` object, never the route promise. Queries sit in
`<folder>-queries.ts` with `import "server-only"`, actions in
`<folder>-actions.ts`, and pure helpers a page needs (a scope, a filter parser)
in `<folder>-cache.ts`. A tag you write yourself lives in `<folder>-cache.ts` too, built with `tagFor` (ADR 0311). An async component in `components/` exports its
`*Skeleton` in the same file, or carries `// skeleton: <reason>` above it. Use
`io()` from `next/cache` for a clock or random read, and `connection()` only
with a comment that states why rendering has to wait for a request. Read
`.agents/skills/nextjs-app-architecture` before you add a feature.

A page under `(app)` exports `instant = true`, or carries `// instant: <reason>`
above its default export; `ensureStatic` is `"shell"` or `"prefetch"`. Pages that
do not export `instant` yet sit in `scripts/app-architecture-allow.json`, and the
list only shrinks as each area is converted. `apps/examples/nextjs/tests/routes.manifest.ts`
lists every page with its archetype, seeded URL and database budget, and
`routes-manifest.test.ts` fails when a page has no entry. The manifest generates
one `expectInstant` case per instant page (`instant-routes.spec.ts`), one budget
per route (`budgets.spec.ts`) and the cold, warm and client timings
(`cold-warm.spec.ts`); `pnpm example:perf-report` merges the numbers.

## Library specs

The example app cannot do these without a change in `packages/better-supabase`
(and `packages/next-config` where named). Each entry says what to build, where,
and how to prove it; none is implemented yet. ADR 0316 records the decision.

### `AuthGate`

Build: `better-supabase/next/auth-gate`, a Server Component that `init` writes
into `app/[locale]/(app)/layout.tsx`. Export `AuthGate({ children, fallback =
null, redirect })` and a client `useUser()` hook.

- The layout stays synchronous. `AuthGate` renders `<Suspense fallback>` around
  an inner async component that creates one promise with `bsb.user()` and passes
  it through a context provider. Client leaves call `use(userPromise)` inside
  their own boundary and never import the data layer.
- `bsb.user()` is a `"use cache: private"` function with `cacheLife({ stale:
  300 })` that returns `{ id, email, name, organizationId }`. It never returns
  the token or the session.
- The session check (`redirect`, `forbidden`, `unauthorized`) runs before the
  first `<Suspense>`, so the status code is right; the proxy keeps the
  cookie-only redirect for signed-out visitors.
- User-scoped subtrees get `key={userId}`, so a user change never shows another
  user's DOM.

Prove it: `tests/next` renders the layout with an ended session (expects a 307)
and a valid one (expects the shell in the first chunk and one token
verification, asserted with `expectRequestStats`); a type test shows that
`useUser()` returns no token field. Size: `next + client` in
`tests/bundle/baseline-shipped.json` does not grow.

### `bsb.cached(options, { stage })`

Build: add `stage?: "prefetch" | "navigation"` to `CachedOptions` in
`src/next/types.ts` and apply it in `create.ts` before the scope opens.

- `stage: "navigation"` awaits `navigation()` from `next/cache`, and `stage:
  "prefetch"` awaits `prefetch()`, in the calling component, before
  `applyEntry` runs and never inside the `"use cache"` scope (the gates throw in
  one).
- `bsb.bootstrap` takes the same option.
- Without Cache Components or Partial Prefetching the option is a no-op that
  logs once in development.
- Add `life?: CachedLife | "max"` so an app names the profile instead of
  calling `cacheLife("max")` after `bsb.cached()` (ADR 0312). `"max"` means
  `{ stale: 300, revalidate: 2592000, expire: 31536000 }`; the token cap of
  `capToToken` still applies.

Prove it: a `tests/next` case per stage that records the order of `navigation()`
and the first query, and a case that `life: "max"` yields the `max` profile.
Export snapshot and `api/exports.json` change (`vitest run tests/exports.test.ts
-u`); the docs page for `bsb.cached` gains both options.

### `better-supabase/next/proxy`

Build: a new subpath whose entry is `src/next/proxy-entry.ts`, exporting
`createProxy()` and the helpers `proxy.ts` uses (`mutableResponse`,
`overrideRequestHeaders`, `syncMiddlewareSetCookie`, `serverTimingValue`).

- The entry imports `src/next/proxy.ts`, the session refresh of ADR 0117 and the
  cookie-only optimistic redirect, and nothing from `create.ts`. Today `create.ts`
  statically imports `sign-in.ts`, `record.ts`, `collector.ts` and
  `resources.ts`, so the proxy bundle carries Server Component code.
- Add the subpath to the exports map, `tsdown.config.ts`, `README.md`'s table,
  the export snapshot and the docs under `apps/docs/content/docs`; add it to
  neither `NODE_ENTRIES` list (it imports no Node built-in).
- The example's `src/proxy.ts` imports it.

Prove it: a new entry in `tests/bundle/baseline-shipped.json` smaller than
`next`, and `tests/standards/wintertc.test.ts` passes for it.

### Taint

Build: `createNextConfig()` sets `experimental.taint: true`
(`packages/next-config/src/next-config.ts`). `createNext` calls
`experimental_taintUniqueValue` on the access and refresh tokens and
`experimental_taintObjectReference` on the `ServerContext`, `AuthState` and the
`bsb.admin()` context, behind a guard for React builds without the API. The
Supabase clients a context creates are not tainted, as `next.mdx` says.

Prove it: a `tests/next` case passes a tainted object and a tainted token to a
client component and expects the React taint error; the DTO rule (`bsb.user()`)
stays the first layer, taint the second.

### Offline and PWA files

Build: the controllers of ADR 0030 read `useOffline()` from `next/offline`: a
list or record pauses refetches and exposes `offline: true` instead of an
error, and a write queues once and retries when the navigation layer retries.
`useOffline()` is `false` during SSR and hydration, so no mismatch. The
controllers stay idempotent under double effects and mutate no props.

`init` for Next.js also writes `app/manifest.ts`, a service worker served with
the `no-cache, no-store, must-revalidate` header `createNextConfig` already
sets, and `NEXT_PUBLIC_VAPID_PUBLIC_KEY` and `VAPID_PRIVATE_KEY` in
`.env.example` without values.

Prove it: `tests/types` for the `offline` field, a controller test with
`useOffline` mocked to `true`, and the example's offline e2e.

### The `init` fixture

`init` for Next.js must write the layout `scripts/check-app-architecture.ts`
checks: `app/`, `features/<domain>/<domain>-queries.ts` (`server-only`),
`<domain>-actions.ts` (`'use server'`), `components/<name>.tsx` with a sibling
`*Skeleton`, `<domain>-cache.ts` for tags, and synchronous pages that resolve
`params` with `params.then()`. Commit the generated output under
`tests/init-fixture/nextjs/src`; the check script already lists that path in
`pendingRoots` and fails on findings as soon as the directory exists.

## First-load JavaScript and the bundle analyzer

`tests/next-build` holds every route's first load to `baseline.json` (raw bytes
never rise, compressed bytes may move by 64). To see what a route ships and why,
use the Turbopack analyzer from Next.js 16.4 (ADR 0481). `--output` writes the
analysis without starting the UI and `--snapshot` names it:

```bash
cd apps/examples/nextjs
pnpm exec next analyze --output --snapshot before
pnpm exec next analyze export --snapshot before \
  | node ../../../scripts/next-analyze-report.ts "/[locale]/customers" 25
pnpm exec next analyze            # the interactive UI, with import chains
```

The report groups a route's synchronous client chunks by package. In the UI,
open a module to see the import chain that includes it, and switch between the
client and server views. `next analyze` builds on its own and writes under
`.next/diagnostics/analyze`; run `rm -rf .next` before a real `next build`
afterwards, or the prerender fails with a duplicate-React error.

Rules the example follows (ADR 0480):

- A route outside `(app)` never imports `@/lib/supabase/client`, `@/lib/hooks` or a
  `@/hooks/*` file. Forms that call Auth await `loadBrowserClient()` on submit.
- A menu, dialog or sheet that most visits never open loads on first intent
  (`LazyOnIntent`) or on first open. Toasts go through `@/lib/toast`.
- Browser code reads the global `Temporal` and never imports `temporal-polyfill`
  (ADR 0482).
