---
"better-supabase": minor
---

Add `bsb.auth()`, `bsb.tenant(ref, permission?, options?)` and `bsb.activeTenant()` to `createNext` for cached reads. They resolve the tenant through the new `tenants` option, check the caller, and end the render with `unauthorized()`, `notFound()` or `forbidden()` when the caller is refused. Add `.orNull()` and `.or(fallback)` to every read result: a `not_found` error becomes `null` or the fallback, other errors throw.

| Before                                 | After                                        |
| -------------------------------------- | -------------------------------------------- |
| a `null` ladder around `bsb.cached()`  | `await bsb.tenant(org, permission, options)` |
| `result.orThrow()` plus a `null` check | `result.orNull()`                            |
| `bsb.tenant()` (root param, unchanged) | `bsb.tenant()` or `bsb.activeTenant()`       |
