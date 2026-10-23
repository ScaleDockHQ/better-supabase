---
"better-supabase": minor
---

Framework adapters now come in two tiers. Next.js, Hono, Expo Router, SvelteKit, TanStack Start and React Router are supported adapters: they get the full test matrix, an example app and every new guide. Astro, Edge Functions, Elysia, H3, Nuxt and Nitro 2 (`better-supabase/h3/v1`), NestJS, Node and SolidStart are community adapters: they keep shipping in every release with a smoke test that serves a request, and their docs pages carry a community note. No adapter is removed and no import changes. Read more under [adapter tiers](https://bettersupabase.com/docs/frameworks#adapter-tiers) and in ADR 0094.
