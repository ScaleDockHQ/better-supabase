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
  `<html>`, fonts and `metadataBase`.

## Instant navigation tests

The Next.js example proves its navigations with `@next/playwright`'s
`instant()` (`apps/examples/nextjs/e2e`, run with `test:e2e`).
`instant-nav.rig.md` next to it records the build, the users and the
contracts.

- Never measure on `next dev`. The verdict comes from `next build` with
  `EXPOSE_TESTING_API=1` and `next start`; Playwright's `webServer` builds
  with it. A build without the testing API passes every test vacuously.
- Build `packages/better-supabase` first in a fresh worktree; the example
  imports its `dist`.
- Before trusting a GREEN, show that the spec can go RED: remove the cache
  scope the contract depends on (replace `"use cache: private"` and
  `bs.cached()` in `getCustomers` with `bs.context()`; `bs.cached()` alone
  outside a cache scope throws) and watch the rows disappear under the lock. No retries and no timeouts in
  `instant()` specs.
- Routes you left stay mounted in a hidden `<Activity>`, and a streamed
  Suspense boundary sits in a hidden `<div>` for a moment, so the same test
  id, label or text can match twice. Use the visible-only helpers in
  `e2e/nav.ts`, and `useId()` for form ids instead of fixed strings.
- Content that reads `params` can't be in the route's shared App Shell. A
  link to such a page needs `prefetch` to resolve its cached reads before
  the click (the customer rows in `customer-table.tsx`).
- A database budget (`maxCalls`, `maxWaves`) fails on a navigation served
  entirely from the client cache, because no response carries
  `x-bs-request-id`. Budget only navigations that reach the server.

## Lint needs generated Next types

`PageProps<Route>` and `next/root-params` come from `next typegen` (`.next/types`).
The example `lint` script runs typegen first so type-aware Oxlint has them on a
clean CI checkout. Local `next dev` leaves those files around, which hid the
gap. Docs and marketing do not use those names, so their `lint` stays `oxlint`.

## The example app

- `protect` in `src/proxy.ts` runs on GET and HEAD only. Server Actions post
  to the current URL, and a guest-only redirect on that POST breaks sign-in.
- `refresh()` from a Server Action doesn't evict prefetched private App
  Shells. After the session changes (sign-in, organization switch), call
  `router.refresh()` on the client after `router.push`
  (`use-refresh-session.ts`), and don't link to a page whose signed-out
  prefetch is a redirect (the brand in the auth layout).
- next-intl reads `.po` catalogs keyed by `msgctxt` only with the header
  `X-Message-Key: msgctxt`; without it the keys are dropped and every message
  is missing.
- A shadcn `Button` with `render={<Link />}` gives the link `role="button"`.
  Style the link with `buttonVariants()` instead.
- `Math.random()` during render fails the prerender, including skeleton
  widths; use a fixed list.

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
