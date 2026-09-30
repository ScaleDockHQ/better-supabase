# Next.js in docs and marketing

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
  in `apps/docs/components/ask-ai.tsx` does.
- `experimental.globalNotFound` needs `app/global-not-found.tsx` with its own
  `<html>`, fonts and `metadataBase`.

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
