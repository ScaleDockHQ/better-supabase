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
  404 instead. In the example, `[locale]` matches every path, so unknown
  `/api` paths answer from `app/api/[...rest]/route.ts`.
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
  prop (`security-queries.ts` for the two-factor and connected agents cards).
  `supabase.auth` is off on the server client, which passes `accessToken`, so
  those reads call the Auth REST endpoints with `auth.token`.
- A database budget (`maxCalls`, `maxWaves`) fails on a navigation served
  entirely from the client cache, because no response carries
  `x-bsb-request-id`. Budget only navigations that reach the server.

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
- The commit hook runs `ultracite fix` on the staged files, and it fails
  with "No files found" when every staged file is lint-ignored (generated
  clients alone). Commit generated files with the change that needs them.
- After `git mv`, stage the edited file again: the hook lints the staged
  content, not the working tree.
- Permissions with overrides live in the database, not in the token, so a
  proxy check costs one round trip before the first byte of every gated page.
  The example redirects from `PermissionRedirect` instead, which runs after
  the shell on the permissions `AppNav` already reads.
- Start a private read together with `getPermissions()` instead of after it.
  Two reads in a row keep the response open for two round trips, and Chrome
  holds a reload of the same URL until that response ends (its HTTP cache
  lock), so a reload looks slow even when the server answers at once.

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
