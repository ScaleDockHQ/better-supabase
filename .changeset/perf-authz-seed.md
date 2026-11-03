---
"better-supabase": minor
---

Add `createVersionCache({ store, maxStaleMs })` to `better-supabase/server`, a `subject` option on the sessions `bootstrap` entries that `bsb.bootstrap` returns and `accessFor` passes to authorizers as `runtime.seed` (`AuthzSubjectSeed`), and doctor code BS611 for a service-role client inside a `"use cache: private"` function.
