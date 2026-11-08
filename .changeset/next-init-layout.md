---
"better-supabase": minor
---

`init` for Next.js writes the feature-sliced `app/`, `features/` and `components/` layout that `check:app-architecture` holds the example to (an `AuthGate` layout, a synchronous page that passes `params.then()` to a feature, `*-queries.ts`, `*-actions.ts` and `*-cache.ts` files, async components with skeletons), plus `app/manifest.ts`, `public/sw.js`, `public/offline.html` and the Web Push keys in `.env.example`. The proxy matcher skips `html` and `webmanifest`. Existing files are kept.
