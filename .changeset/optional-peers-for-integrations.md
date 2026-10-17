---
"better-supabase": minor
---

`@openfeature/server-sdk`, `@supabase-labs/middleware-openfeature`, `@vercel/connect`, `@ai-sdk/anthropic`, `@powersync/common` and `flags` are now optional peer dependencies. better-supabase still imports none of them, so nothing new is installed, but your package manager now warns when one of them is outside the major versions the conformance tests cover. The ranges are on the [Peers](https://bettersupabase.com/docs/getting-started/peers) page.
