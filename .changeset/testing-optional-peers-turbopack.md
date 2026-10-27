---
"better-supabase": patch
---

`better-supabase/testing` no longer pulls `@supabase/lite` or `@next/playwright` into a Turbopack bundle. Both loaded through a specifier held in a `const`, which Turbopack folds and resolves, so an app that imported `seedTenantOnCreate` from `instrumentation.ts` failed to compile on `@supabase/pg-delta`. They now load through the same bundler-ignored import as the other optional peers.
