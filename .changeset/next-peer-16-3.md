---
"better-supabase": minor
---

`better-supabase/next` now needs Next.js 16.3 or later: the `next` peer range is `>=16.3 <17`, because `createNext` awaits `io()`, which Next.js added in 16.3. On 16.0 to 16.2, upgrade Next.js before you upgrade better-supabase.
