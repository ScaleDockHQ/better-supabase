---
"better-supabase": minor
---

The frameworks the adapters support are now optional peer dependencies: `react-router` (7.9 to 8), `@sveltejs/kit` (2 and 3), `h3` (1 and 2), `nuxt` (3 and 4), `astro` (7), `@solidjs/start` (2), `@tanstack/react-start` (1), `elysia` (1), `express` (5), `fastify` (5) and `koa` (3). Nothing new is installed, but your package manager now warns when a framework is outside the majors the conformance tests cover. The ranges are on the [Peers](https://bettersupabase.com/docs/getting-started/peers) page.

The conformance tests found these fixes:

- `better-supabase/h3` and `better-supabase/solid-start` read the Cloudflare bindings from `event.req.runtime.cloudflare.env`, where Nitro 3 puts them. Before, `getEnv` found no bindings on Cloudflare with H3 2 or SolidStart 2.
- The SvelteKit `handle` type-checks as SvelteKit's `Handle` (SvelteKit 2 and 3), so it works inside `sequence()`.
- The SvelteKit adapter calls `error(status, message)` instead of the `error(status, { message })` form SvelteKit 3 deprecated. A custom `kit.error` now receives the message as a string.
- The TanStack Start middleware accepts a `next()` that returns its result without a promise.
- The Astro image service accepts any `quality` string. A string other than `low`, `mid`, `high` or `max` uses the default quality.
- The Nuxt module type-checks as a module for Nuxt 3 as well as Nuxt 4.
