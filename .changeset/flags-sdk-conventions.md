---
"better-supabase": minor
---

`better-supabase/flags-sdk` follows the Flags SDK's adapter conventions (breaking). `betterSupabaseAdapter` is now a ready adapter that reads `SUPABASE_URL` and `SUPABASE_SECRET_KEY` on first use; pass it to `flag()` as `adapter: betterSupabaseAdapter`. The old factory is `createBetterSupabaseAdapter`, which also takes `url` and `secretKey` and an `identify` every flag on it shares. `createIdentify({ server })` reads the session from the request without refreshing it, and `visitor` gives signed-out requests a stable rollout bucket. `getProviderData(adapter, { flags })` joins the declared flags for Flags Explorer. `pnpm better-supabase codemod 0.32` renames the calls.

| 0.31                             | 0.32                                   |
| -------------------------------- | -------------------------------------- |
| `betterSupabaseAdapter(options)` | `createBetterSupabaseAdapter(options)` |
| `adapter: bsFlags()`             | `adapter: bsFlags`                     |
| `createIdentify({ claims })`     | `createIdentify({ server: bsb })`      |
