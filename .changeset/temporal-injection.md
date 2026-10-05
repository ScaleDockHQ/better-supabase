---
"better-supabase": minor
---

Pass `Temporal` without patching `globalThis`: `defineSupabase(schema, { temporal })` takes the namespace (`import { Temporal } from "temporal-polyfill"`), and every API that reads Temporal (decoded rows, the default clock, plugins, jobs, webhooks, storage) uses it, with `globalThis.Temporal` as the fallback. `betterSupabase.temporal` returns the namespace in use, and `provideTemporal()` sets it for helpers you call without a definition. The generated Valibot and Zod schemas check Temporal values with the new `isInstant` and `isPlainDateTime` guards, which compare `Symbol.toStringTag`, so they no longer read `Temporal` when the module loads; run `better-supabase gen` to pick this up. `isPlainDate`, `isPlainTime` and `isZonedDateTime` are exported too.
