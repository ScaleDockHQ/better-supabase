---
"better-supabase": minor
---

Install the packages the CLI reads and plans with. `oxc-parser`, `@supabase/pg-parser`, `@supabase/pg-delta` and `@supabase/pg-topo` are now exact-pinned dependencies of `better-supabase`, and only the CLI and the Node entries import them, so deployed functions do not grow. Remove `@supabase/pg-delta` and `@supabase/pg-topo` from your own `package.json`: doctor reports a second entry as BS709, and BS239 (the two packages are missing) is retired.
