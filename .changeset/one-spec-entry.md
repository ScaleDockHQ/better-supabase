---
"better-supabase": minor
---

`better-supabase/spec` is the one entry for API documents. It exports the
OpenAPI, AsyncAPI, Arazzo and Overlay renderers (`createOpenApi`,
`createAsyncApi`, `createArazzo`, `defineWorkflow`, `applyOverlays`,
`defineOverlay` and the rest) next to `defineApi`. The subpaths
`better-supabase/openapi`, `better-supabase/asyncapi`,
`better-supabase/arazzo` and `better-supabase/overlay` are removed: import
the same names from `better-supabase/spec`. `better-supabase codemod 0.15`
rewrites the imports, and doctor reports BS418 for any that are left.
